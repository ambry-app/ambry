defmodule Ambry.Repo.Migrations.DropLegacyPlayerStateTables do
  use Ecto.Migration

  use Familiar

  # Removes the legacy (pre-event-sourcing) playback-state storage:
  #
  # - `player_states` — replaced by `playback_events` + derived `playthroughs_new`
  # - `playthroughs` — the v1 sync table; v2 derives all state from events
  # - `users.loaded_player_state_id` — only used by the removed web player
  #
  # The `users_flat` view is rebuilt (v2) to derive its progress counts from
  # `playthroughs_new` instead of `player_states`.
  #
  # This migration is irreversible: rolling back would require restoring the
  # legacy tables' data from a backup anyway.
  def up do
    drop_view("users_flat")

    alter table(:users) do
      remove :loaded_player_state_id
    end

    drop table(:player_states)
    drop table(:playthroughs)

    create_view("users_flat", version: 2)
  end

  def down do
    raise Ecto.MigrationError,
      message: "cannot restore legacy player-state tables; restore from backup instead"
  end
end
