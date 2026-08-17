defmodule Ambry.Repo.Migrations.RetirePlacedSourceColumns do
  @moduledoc """
  Clears `source_path` and `source_files` on every recording that has tracks.

  Those two columns are the transcode pipeline's bookkeeping: the folder and
  the files a processor was pointed at when it produced a recording's
  mpd/hls/mp4. Placement started filling them in with the *library copies*
  of an imported recording — a recording nothing ever transcoded — so they
  claimed a transcode that never ran, from inputs that are in fact the
  recording's own served tracks.

  Nothing reads them for such a recording; `media_tracks` is what it is
  served from, organized by and deleted with. The writers have stopped, and
  this clears the rows they already wrote.

  The down migration reconstructs the values from `media_tracks` rather than
  pretending to restore an original, because that is exactly where they came
  from.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE media
    SET source_path = NULL, source_files = '{}'
    WHERE EXISTS (SELECT 1 FROM media_tracks WHERE media_tracks.media_id = media.id)
    """)
  end

  def down do
    execute("""
    UPDATE media SET
      source_files = tracks.paths,
      source_path = regexp_replace(tracks.paths[1], '/[^/]*$', '')
    FROM (
      SELECT media_id, array_agg(path ORDER BY index) AS paths
      FROM media_tracks
      GROUP BY media_id
    ) AS tracks
    WHERE tracks.media_id = media.id AND media.source_path IS NULL
    """)
  end
end
