defmodule Ambry.Repo.Migrations.SplitLocationsIntoSourcesAndRoots do
  use Ecto.Migration

  @moduledoc """
  Sources and library roots are separate concepts and now live in separate
  tables. A source is watched and read, and carries the one property that
  ever mattered: whether its files can be trusted to stay (`on_import`).
  A root is written and never watched. The old three-kind taxonomy mapped:
  downloads → a bring-in source, external_collection → a leave-in-place
  source, library_root → a root.

  Ids are preserved on both sides (each old row lands in exactly one new
  table), which is what keeps `inbox_items.source_id` and the root ids
  embedded in stored draft JSON valid without rewriting them.

  A previously *enabled* library_root was also being watched, so it gets a
  companion leave-in-place source over the same path — watching is a
  source's job now. Items discovered under a root re-point to that
  companion; items under a disabled root fall back to "ad-hoc scan" (nil).
  """

  def up do
    create table(:library_roots) do
      add :name, :string, null: false
      add :path, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:library_roots, [:name])
    create unique_index(:library_roots, [:path])

    create table(:sources) do
      add :name, :string, null: false
      add :path, :string, null: false
      add :on_import, :string, null: false
      add :import_policy, :string
      add :enabled, :boolean, default: true, null: false
      add :last_scanned_at, :utc_datetime
      add :target_root_id, references(:library_roots, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sources, [:name])
    create unique_index(:sources, [:path])
    create index(:sources, [:target_root_id])

    execute("""
    INSERT INTO library_roots (id, name, path, inserted_at, updated_at)
    SELECT id, name, path, inserted_at, updated_at
    FROM library_locations WHERE kind = 'library_root'
    """)

    execute("""
    INSERT INTO sources
      (id, name, path, on_import, import_policy, enabled, last_scanned_at,
       target_root_id, inserted_at, updated_at)
    SELECT id, name, path,
      CASE kind WHEN 'downloads' THEN 'bring_in' ELSE 'leave_in_place' END,
      import_policy, enabled, last_scanned_at, target_root_id,
      inserted_at, updated_at
    FROM library_locations WHERE kind IN ('downloads', 'external_collection')
    """)

    execute("""
    SELECT setval(
      pg_get_serial_sequence('library_roots', 'id'),
      (SELECT COALESCE(MAX(id), 0) + 1 FROM library_locations), false
    )
    """)

    execute("""
    SELECT setval(
      pg_get_serial_sequence('sources', 'id'),
      (SELECT COALESCE(MAX(id), 0) + 1 FROM library_locations), false
    )
    """)

    # Watching is a source's job now: an enabled root keeps being watched
    # through a companion source over the same path.
    execute("""
    INSERT INTO sources
      (name, path, on_import, enabled, last_scanned_at, inserted_at, updated_at)
    SELECT name, path, 'leave_in_place', enabled, last_scanned_at,
      inserted_at, updated_at
    FROM library_locations WHERE kind = 'library_root' AND enabled = true
    """)

    execute("ALTER TABLE inbox_items DROP CONSTRAINT IF EXISTS inbox_items_location_id_fkey")
    rename table(:inbox_items), :location_id, to: :source_id

    # Items discovered under a watched root re-point to its companion source.
    execute("""
    UPDATE inbox_items SET source_id = s.id
    FROM library_locations l JOIN sources s ON s.path = l.path
    WHERE l.kind = 'library_root' AND inbox_items.source_id = l.id
    """)

    # Anything still dangling (items under a disabled root) becomes an
    # ad-hoc-scan item rather than a broken reference.
    execute("""
    UPDATE inbox_items SET source_id = NULL
    WHERE source_id IS NOT NULL AND source_id NOT IN (SELECT id FROM sources)
    """)

    alter table(:inbox_items) do
      modify :source_id, references(:sources, on_delete: :nilify_all)
    end

    drop table(:library_locations)
  end

  def down do
    create table(:library_locations) do
      add :name, :string, null: false
      add :path, :string, null: false
      add :kind, :string, null: false
      add :import_policy, :string
      add :enabled, :boolean, default: true, null: false
      add :last_scanned_at, :utc_datetime
      add :target_root_id, references(:library_locations, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:library_locations, [:name])
    create unique_index(:library_locations, [:path])

    execute("""
    INSERT INTO library_locations
      (id, name, path, kind, enabled, last_scanned_at, inserted_at, updated_at)
    SELECT id, name, path, 'library_root', true, NULL, inserted_at, updated_at
    FROM library_roots
    """)

    # Companion watch-sources over a root's path can't come back as rows —
    # the path is taken — so they fold back into the root they watched.
    execute("""
    INSERT INTO library_locations
      (id, name, path, kind, import_policy, enabled, last_scanned_at,
       target_root_id, inserted_at, updated_at)
    SELECT id, name, path,
      CASE on_import WHEN 'bring_in' THEN 'downloads' ELSE 'external_collection' END,
      import_policy, enabled, last_scanned_at, target_root_id,
      inserted_at, updated_at
    FROM sources
    WHERE path NOT IN (SELECT path FROM library_roots)
    """)

    execute("""
    SELECT setval(
      pg_get_serial_sequence('library_locations', 'id'),
      (SELECT COALESCE(MAX(id), 0) + 1 FROM library_locations), false
    )
    """)

    execute("ALTER TABLE inbox_items DROP CONSTRAINT IF EXISTS inbox_items_source_id_fkey")
    rename table(:inbox_items), :source_id, to: :location_id

    execute("""
    UPDATE inbox_items SET location_id = NULL
    WHERE location_id IS NOT NULL
      AND location_id NOT IN (SELECT id FROM library_locations)
    """)

    alter table(:inbox_items) do
      modify :location_id, references(:library_locations, on_delete: :nilify_all)
    end

    drop table(:sources)
    drop table(:library_roots)
  end
end
