defmodule Ambry.Repo.Migrations.AddMediaIdToPlaybackEvents do
  use Ecto.Migration

  def up do
    # Add media_id column to playback_events
    # Only required for 'start' events - identifies which media the playthrough is for
    alter table(:playback_events) do
      add :media_id, references(:media)
    end

    # Backfill media_id on existing start events from their playthrough's media_id
    execute """
    UPDATE playback_events e
    SET media_id = p.media_id,
        position = 0,
        playback_rate = 1.0
    FROM playthroughs p
    WHERE e.playthrough_id = p.id
    AND e.type = 'start'
    AND e.media_id IS NULL
    """
  end

  def down do
    alter table(:playback_events) do
      remove :media_id
    end
  end
end
