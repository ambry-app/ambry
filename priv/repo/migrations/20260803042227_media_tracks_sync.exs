defmodule Ambry.Repo.Migrations.MediaTracksSync do
  use Ecto.Migration

  # Lets clients learn that a track went away, the same way they learn about
  # every other deleted record: a BEFORE DELETE trigger writes a row into
  # `deletions`, which `deletionsSince` hands out.
  def up do
    execute """
    CREATE TRIGGER track_delete_trigger
    BEFORE DELETE ON media_tracks
    FOR EACH ROW
    EXECUTE FUNCTION track_delete('media_track');
    """
  end

  def down do
    execute "DROP TRIGGER track_delete_trigger ON media_tracks;"
    execute "DELETE FROM deletions WHERE type = 'media_track'"
  end
end
