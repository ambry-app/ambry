defmodule Ambry.Repo.Migrations.BackfillStartEventDeviceIds do
  use Ecto.Migration

  def up do
    execute("""
    WITH earliest_device_per_playthrough AS (
      SELECT DISTINCT ON (playthrough_id)
        playthrough_id,
        device_id
      FROM playback_events
      WHERE device_id IS NOT NULL
      ORDER BY playthrough_id, timestamp ASC
    )
    UPDATE playback_events pe
    SET device_id = e.device_id
    FROM earliest_device_per_playthrough e
    WHERE pe.playthrough_id = e.playthrough_id
      AND pe.type = 'start'
      AND pe.device_id IS NULL
    """)
  end

  def down do
    # Data migration - cannot be reversed
    :ok
  end
end
