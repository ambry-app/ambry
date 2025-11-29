defmodule Ambry.Repo.Migrations.MigratePlayerStatesToPlaythroughs do
  @moduledoc """
  Migrates existing PlayerState records to the new Playthrough + PlaybackEvent model.

  For each PlayerState, this creates:
  1. A Playthrough with:
     - id: new UUID
     - status: mapped from player_state.status
     - started_at: player_state.inserted_at

  2. A synthetic PlaybackEvent with:
     - type: "pause" (representing last known state)
     - device_id: nil (migration marker)
     - timestamp: player_state.updated_at
     - position: player_state.position
     - playback_rate: player_state.playback_rate

  Note: Historical listening time is lost (no play/pause pairs), but position is preserved.

  PlayerStates with status 'not_started' are skipped - in the new model, a book that
  hasn't been started simply has no playthrough record.
  """

  use Ecto.Migration

  def up do
    # Note: We set device_id to NULL for migrated events to mark them as
    # migration-created (no physical device recorded the event)
    #
    # We skip 'not_started' player states - in the new model, a book that hasn't
    # been started simply has no playthrough record.
    execute("""
    INSERT INTO playthroughs (id, user_id, media_id, status, started_at, finished_at, abandoned_at, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      ps.user_id,
      ps.media_id,
      ps.status::text,
      ps.inserted_at,
      CASE WHEN ps.status = 'finished' THEN ps.updated_at ELSE NULL END,
      NULL,
      ps.inserted_at,
      ps.updated_at
    FROM player_states ps
    WHERE ps.status != 'not_started'
    """)

    # Now insert synthetic pause events for each migrated playthrough
    # We need to join back to player_states to get the position/rate
    execute("""
    INSERT INTO playback_events (id, playthrough_id, device_id, type, timestamp, position, playback_rate)
    SELECT
      gen_random_uuid(),
      p.id,
      NULL,
      'pause',
      ps.updated_at,
      ps.position,
      ps.playback_rate
    FROM playthroughs p
    INNER JOIN player_states ps ON ps.user_id = p.user_id AND ps.media_id = p.media_id AND ps.inserted_at = p.started_at
    """)
  end

  def down do
    # Remove all migrated data
    # Note: This will delete ALL playthroughs and events, not just migrated ones
    # In practice, you'd want to be more careful here
    execute("DELETE FROM playback_events")
    execute("DELETE FROM playthroughs")
  end
end
