defmodule Ambry.Repo.Migrations.PlacementIsNotASourceSetting do
  @moduledoc """
  Drops the two placement fields from `sources`.

    * `import_policy` — hardlink / symlink / copy / move is a property of the
      **pairing**, not of the input. Whether a hardlink is even possible
      depends on the source and the root sharing a filesystem, which one end
      cannot know. It was never binding either: every import could change it,
      which makes it a default, and a default belongs where it can be
      learned. `import_preferences` learns it.

    * `target_root_id` — a preferred root, which the same table now supplies
      from the root the source last imported into. Keeping both would mean
      two mechanisms for one job with a precedence question, and the loser is
      always the configured one: it is consulted before the first import and
      shadowed forever after. A field that silently stops mattering is worse
      than either mechanism alone.

  What is lost, deliberately: a fresh install can no longer declare "this
  source goes to that root" before importing anything. With one root nothing
  changes — it resolves silently either way. With several, the first import
  asks, which is the honest answer to a genuinely ambiguous question, and
  the memory answers it from then on.

  Existing choices are carried over rather than dropped: each source's
  policy, paired with its preferred root (or the only root, if there is
  one), becomes its first remembered placement. Anything already remembered
  from a real import wins — that is a fact, and this is a translation of a
  setting.
  """

  use Ecto.Migration

  def up do
    # The root a setting implied: the one it named, or the only one there is.
    only_root =
      "(SELECT r.id FROM library_roots r WHERE (SELECT count(*) FROM library_roots) = 1)"

    execute("""
    INSERT INTO import_preferences
      (source_id, library_root_id, policy, last_used_at, inserted_at, updated_at)
    SELECT s.id, coalesce(s.target_root_id, #{only_root}), s.import_policy, now(), now(), now()
      FROM sources s
     WHERE s.import_policy IS NOT NULL
       AND coalesce(s.target_root_id, #{only_root}) IS NOT NULL
    ON CONFLICT (source_id, library_root_id) DO NOTHING
    """)

    alter table(:sources) do
      remove :import_policy
      remove :target_root_id
    end
  end

  def down do
    alter table(:sources) do
      add :import_policy, :string
      add :target_root_id, references(:library_roots, on_delete: :nilify_all)
    end

    execute("""
    UPDATE sources s
       SET import_policy = p.policy,
           target_root_id = p.library_root_id
      FROM (SELECT DISTINCT ON (source_id) source_id, library_root_id, policy
              FROM import_preferences
             ORDER BY source_id, last_used_at DESC, id DESC) p
     WHERE p.source_id = s.id
    """)

    execute("UPDATE sources SET import_policy = 'hardlink' WHERE import_policy IS NULL")

    execute("ALTER TABLE sources ALTER COLUMN import_policy SET NOT NULL")
    execute("ALTER TABLE sources ALTER COLUMN import_policy SET DEFAULT 'hardlink'")
  end
end
