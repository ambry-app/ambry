defmodule Ambry.Repo.Migrations.DropBookmarks do
  use Ecto.Migration

  # Removes the orphaned `bookmarks` table.
  #
  # Bookmarks were a web-player-only feature: they were never exposed over
  # GraphQL, so no mobile client ever created or read one, and the web player
  # itself was removed in v1.7.0. The table has had no UI since.
  #
  # This migration is irreversible and destroys whatever rows survive: restore
  # from a backup if the data is ever wanted.
  def up do
    drop table(:bookmarks)
  end

  def down do
    raise Ecto.MigrationError,
      message: "cannot restore dropped bookmarks; restore from backup instead"
  end
end
