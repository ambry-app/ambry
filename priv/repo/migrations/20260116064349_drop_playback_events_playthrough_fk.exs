defmodule Ambry.Repo.Migrations.DropPlaybackEventsPlaythroughFk do
  use Ecto.Migration

  def change do
    # Drop the FK constraint from playback_events to the legacy playthroughs table.
    # This allows V2 sync to insert events without requiring playthrough entries.
    # The event-sourced playthroughs_new table is derived from events, not the other way around.
    #
    # Future cleanup (once all clients are on V2):
    # 1. Drop the legacy playthroughs table
    # 2. Rename playthroughs_new to playthroughs
    # 3. Re-add the FK constraint
    drop constraint(:playback_events, :playback_events_playthrough_id_fkey)
  end
end
