defmodule Ambry.Repo.Migrations.InboxItemsRequireASource do
  @moduledoc """
  Makes `inbox_items.source_id` mandatory.

  A source-less item came from an ad-hoc scan — `Inbox.discover/1`'s
  bare-path form, which was never reachable from the UI. It stored absolute
  paths where every other item stores source-relative ones, carried no
  placement default, and made "resolve this item's files" a two-shape
  question for every caller. That exception is gone, so the two locatable
  CHECKs lose their `ELSE absolute` halves and state the invariant plainly:
  an inbox path is relative, always.

  Nothing should exist to convert: the only way to create one was from IEx.
  Any that somehow do are deleted rather than assigned a source, because
  guessing which watched folder an absolute path belongs to is exactly the
  quiet re-keying the relative-path invariant exists to prevent. The delete
  is limited to unsettled rows: an imported item is the record of what was
  imported and the only thing keeping an already-imported release from
  resurfacing as a new candidate, so one of those is a fact worth failing
  over rather than discarding.
  """

  use Ecto.Migration

  def up do
    execute("""
    DO $$
    DECLARE stranded integer;
    BEGIN
      SELECT count(*) INTO stranded
        FROM inbox_items WHERE source_id IS NULL AND status = 'imported';

      IF stranded > 0 THEN
        RAISE EXCEPTION
          'inbox_items: % imported row(s) have no source. Point a source at their files and rescan before migrating.',
          stranded;
      END IF;
    END $$;
    """)

    execute("DELETE FROM inbox_items WHERE source_id IS NULL")

    drop constraint(:inbox_items, :inbox_items_path_locatable)
    drop constraint(:inbox_items, :inbox_items_files_locatable)

    # Refused by the database, explained by the app (`delete_source/1`
    # returns reference counts), same as before — `modify` recreates the
    # foreign key, so the `:restrict` has to be restated.
    drop constraint(:inbox_items, "inbox_items_source_id_fkey")

    alter table(:inbox_items) do
      modify :source_id, references(:sources, on_delete: :restrict), null: false
    end

    create constraint(:inbox_items, :inbox_items_path_locatable, check: "path NOT LIKE '/%'")

    create constraint(:inbox_items, :inbox_items_files_locatable,
             check: "ambry_paths_all_relative(files)"
           )
  end

  def down do
    drop constraint(:inbox_items, :inbox_items_path_locatable)
    drop constraint(:inbox_items, :inbox_items_files_locatable)
    drop constraint(:inbox_items, "inbox_items_source_id_fkey")

    alter table(:inbox_items) do
      modify :source_id, references(:sources, on_delete: :restrict), null: true
    end

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
  end
end
