defmodule Ambry.Repo.Migrations.CreatePlaybackTables do
  use Ecto.Migration

  def change do
    # Devices table - tracks client devices that produce events
    create table(:devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :type, :string, null: false

      # Device identification
      add :brand, :string
      add :model_name, :string

      # Browser info (web clients)
      add :browser, :string
      add :browser_version, :string

      # OS info
      add :os_name, :string
      add :os_version, :string

      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:devices, [:user_id])

    # Playthroughs table - represents a user's journey through a book
    create table(:playthroughs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :media_id, references(:media, on_delete: :delete_all), null: false

      add :status, :string, null: false, default: "in_progress"
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :abandoned_at, :utc_datetime
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:playthroughs, [:user_id])
    create index(:playthroughs, [:media_id])
    create index(:playthroughs, [:user_id, :media_id, :status])

    # Playback events table - immutable records of playback actions
    create table(:playback_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :playthrough_id, references(:playthroughs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :device_id, references(:devices, type: :binary_id, on_delete: :nilify_all)

      add :type, :string, null: false
      add :timestamp, :utc_datetime, null: false

      # position and playback_rate are required for playback events (play, pause, seek, rate_change)
      # but NULL for lifecycle events (start, finish, abandon)
      add :position, :decimal
      add :playback_rate, :decimal

      # seek-specific fields
      add :from_position, :decimal
      add :to_position, :decimal

      # rate_change-specific field
      add :previous_rate, :decimal

      # Note: no timestamps - events are immutable
    end

    create index(:playback_events, [:playthrough_id])
    create index(:playback_events, [:playthrough_id, :timestamp])
    create index(:playback_events, [:device_id])
  end
end
