defmodule Ambry.Repo.Migrations.PathConstraints do
  @moduledoc """
  Makes the stored-path invariant structural (PATHS_REFACTOR_PLAN §2.4).

  A stored path is root-relative when the row names a root, and a
  `/uploads/...` path when it doesn't; inbox items are source-relative when
  they have a source and absolute when they don't. These CHECKs are what
  stop the convention regressing in a year — the resolver's refusals
  protect the filesystem, these protect the database.

  Deleting a referenced location is refused by the database, not by
  convention: `library_root_id` and `inbox_items.source_id` become
  `on_delete: :restrict`, paired with app-level deletes that return
  reference counts so the admin UI explains instead of surfacing a
  constraint violation. `sources.target_root_id` deliberately stays
  `nilify_all` — that is a soft *preferred* root, not a dependency.
  """

  use Ecto.Migration

  def up do
    # Array columns need a per-element form; a tiny immutable SQL helper is
    # cleaner than a trigger and usable in a CHECK.
    execute("""
    CREATE FUNCTION ambry_paths_all_relative(paths text[]) RETURNS boolean
    IMMUTABLE LANGUAGE SQL AS
    $$ SELECT coalesce(bool_and(p NOT LIKE '/%'), true) FROM unnest(paths) AS p $$
    """)

    execute("""
    CREATE FUNCTION ambry_paths_all_uploads(paths text[]) RETURNS boolean
    IMMUTABLE LANGUAGE SQL AS
    $$ SELECT coalesce(bool_and(p LIKE '/uploads/%'), true) FROM unnest(paths) AS p $$
    """)

    execute("""
    CREATE FUNCTION ambry_paths_all_absolute(paths text[]) RETURNS boolean
    IMMUTABLE LANGUAGE SQL AS
    $$ SELECT coalesce(bool_and(p LIKE '/%'), true) FROM unnest(paths) AS p $$
    """)

    create constraint(:media_tracks, :media_tracks_path_resolvable,
             check: """
             CASE WHEN library_root_id IS NOT NULL
                  THEN path NOT LIKE '/%'
                  ELSE path LIKE '/uploads/%' END
             """
           )

    create constraint(:media, :media_source_path_resolvable,
             check: """
             source_path IS NULL OR
             CASE WHEN library_root_id IS NOT NULL
                  THEN source_path NOT LIKE '/%'
                  ELSE source_path LIKE '/uploads/%' END
             """
           )

    create constraint(:media, :media_source_files_resolvable,
             check: """
             CASE WHEN library_root_id IS NOT NULL
                  THEN ambry_paths_all_relative(source_files)
                  ELSE ambry_paths_all_uploads(source_files) END
             """
           )

    # Legacy provenance is the pre-refactor exception, quarantined: a
    # recording with a real placement has no business carrying it.
    create constraint(:media, :media_legacy_source_files_quarantined,
             check: "legacy_source_files IS NULL OR library_root_id IS NULL"
           )

    create constraint(:inbox_items, :inbox_items_path_locatable,
             check: """
             CASE WHEN source_id IS NOT NULL
                  THEN path NOT LIKE '/%'
                  ELSE path LIKE '/%' END
             """
           )

    create constraint(:inbox_items, :inbox_items_files_locatable,
             check: """
             CASE WHEN source_id IS NOT NULL
                  THEN ambry_paths_all_relative(files)
                  ELSE ambry_paths_all_absolute(files) END
             """
           )

    # Refused by the database, explained by the app (delete_root/1 and
    # delete_source/1 return reference counts).
    drop constraint(:media, "media_library_root_id_fkey")
    drop constraint(:media_tracks, "media_tracks_library_root_id_fkey")
    drop constraint(:inbox_items, "inbox_items_source_id_fkey")

    alter table(:media) do
      modify :library_root_id, references(:library_roots, on_delete: :restrict)
    end

    alter table(:media_tracks) do
      modify :library_root_id, references(:library_roots, on_delete: :restrict)
    end

    alter table(:inbox_items) do
      modify :source_id, references(:sources, on_delete: :restrict)
    end
  end

  def down do
    drop constraint(:media_tracks, :media_tracks_path_resolvable)
    drop constraint(:media, :media_source_path_resolvable)
    drop constraint(:media, :media_source_files_resolvable)
    drop constraint(:media, :media_legacy_source_files_quarantined)
    drop constraint(:inbox_items, :inbox_items_path_locatable)
    drop constraint(:inbox_items, :inbox_items_files_locatable)

    execute("DROP FUNCTION ambry_paths_all_relative(text[])")
    execute("DROP FUNCTION ambry_paths_all_uploads(text[])")
    execute("DROP FUNCTION ambry_paths_all_absolute(text[])")

    drop constraint(:media, "media_library_root_id_fkey")
    drop constraint(:media_tracks, "media_tracks_library_root_id_fkey")
    drop constraint(:inbox_items, "inbox_items_source_id_fkey")

    alter table(:media) do
      modify :library_root_id, references(:library_roots)
    end

    alter table(:media_tracks) do
      modify :library_root_id, references(:library_roots)
    end

    alter table(:inbox_items) do
      modify :source_id, references(:sources, on_delete: :nilify_all)
    end
  end
end
