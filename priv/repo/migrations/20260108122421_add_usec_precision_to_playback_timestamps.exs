defmodule Ambry.Repo.Migrations.AddUsecPrecisionToPlaybackTimestamps do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      modify :last_seen_at, :utc_datetime_usec, from: :utc_datetime
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end

    alter table(:playthroughs) do
      modify :started_at, :utc_datetime_usec, from: :utc_datetime
      modify :finished_at, :utc_datetime_usec, from: :utc_datetime
      modify :abandoned_at, :utc_datetime_usec, from: :utc_datetime
      modify :deleted_at, :utc_datetime_usec, from: :utc_datetime
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end

    alter table(:playback_events) do
      modify :timestamp, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
