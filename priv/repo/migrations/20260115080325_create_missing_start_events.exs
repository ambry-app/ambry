defmodule Ambry.Repo.Migrations.CreateMissingStartEvents do
  use Ecto.Migration

  # This migration creates synthetic start events for playthroughs that were
  # migrated from the old player_states system without start events.

  def up do
    execute """
    INSERT INTO playback_events (id, playthrough_id, media_id, type, timestamp, position, playback_rate, inserted_at)
    SELECT
      gen_random_uuid(),
      p.id,
      p.media_id,
      'start',
      p.started_at,
      0,
      COALESCE(
        (SELECT e2.playback_rate
         FROM playback_events e2
         WHERE e2.playthrough_id = p.id AND e2.playback_rate IS NOT NULL
         LIMIT 1),
        1.0
      ),
      now()
    FROM playthroughs p
    LEFT JOIN playback_events e ON e.playthrough_id = p.id AND e.type = 'start'
    WHERE e.id IS NULL
    """
  end

  def down do
    # We can't reliably distinguish synthetic start events from real ones,
    # so this migration is not reversible.
    :ok
  end
end
