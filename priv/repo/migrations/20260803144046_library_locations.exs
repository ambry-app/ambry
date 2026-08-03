defmodule Ambry.Repo.Migrations.LibraryLocations do
  use Ecto.Migration

  # Where the library physically is (roadmap 3a).
  #
  # Until now there was exactly one watched folder, and it was an environment
  # variable (`SOURCE_PATH`). That can't express what production actually
  # looks like: the downloads folder and the uploads folder live on two
  # different NAS boxes, and a hardlink cannot cross a filesystem. So a single
  # root can never serve both the legacy transcoded library and new hardlinked
  # imports — multiple roots merging into one logical library is a
  # requirement, not a nicety.
  #
  # One table covers both ends of the pipeline because a library root is also
  # a place worth watching (files hand-placed into the tree have to surface
  # somewhere), and because same-filesystem checks need to compare arbitrary
  # pairs of locations. `kind` is what separates them:
  #
  #   * `downloads`            — messy source. Imports land in the library per
  #                              `import_policy`, and become managed custody.
  #   * `external_collection`  — someone else's organized folder. Adopted in
  #                              place as external custody; never written to.
  #   * `library_root`         — Ambry's own tree, organized by the naming
  #                              template. Managed custody.
  #
  # The legacy uploads library is deliberately NOT registered here: it isn't
  # template-organized and Phase 4's reclaim owns migrating it. It keeps
  # resolving through `Ambry.Paths` exactly as before.
  def change do
    create table(:library_locations) do
      timestamps(type: :utc_datetime)

      # Operator-facing label, so a path change doesn't lose the identity of
      # "the downloads NAS" in the UI or in logs.
      add :name, :text, null: false
      add :path, :text, null: false

      add :kind, :text, null: false

      # `hardlink | copy | move`, and only meaningful for `downloads`. Null
      # everywhere else — the other kinds don't import from anywhere.
      add :import_policy, :text

      # Disabled locations keep their rows and their history; they're just
      # skipped by discovery. Deleting a location is not how you pause one.
      add :enabled, :boolean, null: false, default: true

      add :last_scanned_at, :utc_datetime
    end

    create unique_index(:library_locations, [:path])
    create unique_index(:library_locations, [:name])
    create index(:library_locations, [:kind])

    # Which location an item came from. This is what tells approval whether
    # the files should be hardlinked into a root or adopted where they lie —
    # the custody decision belongs to the location, not to the item.
    #
    # Nullable: items discovered before locations existed have no answer, and
    # inventing one would be worse than admitting it.
    alter table(:inbox_items) do
      add :location_id, references(:library_locations, on_delete: :nilify_all)
    end

    create index(:inbox_items, [:location_id])

    # Carry the existing `SOURCE_PATH` over so a running deployment keeps
    # discovering from the same folder without the operator touching
    # anything. Nothing else reads that variable for discovery after this.
    execute &seed_source_path/0, fn -> :ok end
  end

  defp seed_source_path do
    case System.fetch_env("SOURCE_PATH") do
      {:ok, path} ->
        repo().query!(
          """
          INSERT INTO library_locations
            (name, path, kind, import_policy, enabled, inserted_at, updated_at)
          VALUES ($1, $2, 'downloads', 'hardlink', true, NOW(), NOW())
          ON CONFLICT (path) DO NOTHING
          """,
          ["Downloads", String.trim_trailing(path, "/")]
        )

        :ok

      :error ->
        :ok
    end
  end
end
