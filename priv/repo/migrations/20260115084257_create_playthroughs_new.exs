defmodule Ambry.Repo.Migrations.CreatePlaythroughsNew do
  use Ecto.Migration

  def change do
    create table(:playthroughs_new, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :media_id, references(:media, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Derived status from lifecycle events (start/finish/abandon/resume/delete)
      add :status, :string, null: false

      # Lifecycle timestamps (derived from corresponding events)
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :abandoned_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      # Playback state (derived from most recent playback events)
      add :position, :decimal, null: false
      add :rate, :decimal, null: false

      # Timestamp of most recent event (for sync ordering)
      add :last_event_at, :utc_datetime_usec, null: false

      add :refreshed_at, :utc_datetime_usec, null: false
    end

    create index(:playthroughs_new, [:user_id])
    create index(:playthroughs_new, [:media_id])
    create index(:playthroughs_new, [:user_id, :status])
    create index(:playthroughs_new, [:last_event_at])
  end
end
