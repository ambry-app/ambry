defmodule Ambry.Repo.Migrations.RetirePlacedSourceColumns do
  @moduledoc """
  Clears `source_path` and `source_files` on every recording that has tracks.

  Those two columns state what a transcode consumed. A recording with tracks
  was imported rather than transcoded, so it has no such fact to state, and
  `media_tracks` is what it is served from, organized by and deleted with.

  The down migration reconstructs the values from `media_tracks`, which is
  where they can be derived from.
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
