defmodule Ambry.Repo.Migrations.AddInsertedAtToPlaybackEvents do
  use Ecto.Migration

  # Using up/down instead of change because we need to backfill existing data
  # before adding the NOT NULL constraint

  def up do
    # Step 1: Add column as nullable
    alter table(:playback_events) do
      add :inserted_at, :utc_datetime_usec
    end

    # Step 2: Backfill existing events (inserted_at = timestamp for historical data)
    execute "UPDATE playback_events SET inserted_at = timestamp"

    # Step 3: Add NOT NULL constraint (default handled by Ecto schema)
    alter table(:playback_events) do
      modify :inserted_at, :utc_datetime_usec, null: false
    end

    # Step 4: Index for sync queries (WHERE inserted_at > ?)
    create index(:playback_events, [:inserted_at])
  end

  def down do
    drop index(:playback_events, [:inserted_at])

    alter table(:playback_events) do
      remove :inserted_at
    end
  end
end
