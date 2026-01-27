defmodule Ambry.Repo.Migrations.CreateDevicesUsersTable do
  use Ecto.Migration

  use Familiar

  def up do
    # Create the devices_users linking table
    create table(:devices_users, primary_key: false) do
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :user_id, references(:users, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :last_seen_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:devices_users, [:user_id])

    # Populate from existing events data
    # Join events -> playthroughs_new to get user_id, group by device+user
    execute """
    INSERT INTO devices_users (device_id, user_id, last_seen_at, inserted_at)
    SELECT
      e.device_id,
      p.user_id,
      MAX(e.timestamp),
      NOW()
    FROM playback_events e
    JOIN playthroughs_new p ON e.playthrough_id = p.id
    WHERE e.device_id IS NOT NULL
    GROUP BY e.device_id, p.user_id
    """

    # Update the devices_flat view before dropping columns
    update_view("devices_flat", version: 2, revert: 1)

    # Remove user_id and last_seen_at from devices table
    drop index(:devices, [:user_id])

    alter table(:devices) do
      remove :user_id
      remove :last_seen_at
    end
  end

  def down do
    # Add back user_id and last_seen_at to devices
    alter table(:devices) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :last_seen_at, :utc_datetime
    end

    # Populate from devices_users (pick the most recent user for each device)
    execute """
    UPDATE devices d
    SET user_id = du.user_id, last_seen_at = du.last_seen_at
    FROM (
      SELECT DISTINCT ON (device_id) device_id, user_id, last_seen_at
      FROM devices_users
      ORDER BY device_id, last_seen_at DESC
    ) du
    WHERE d.id = du.device_id
    """

    # Make user_id NOT NULL after populating
    execute "ALTER TABLE devices ALTER COLUMN user_id SET NOT NULL"
    execute "ALTER TABLE devices ALTER COLUMN last_seen_at SET NOT NULL"

    create index(:devices, [:user_id])

    # Revert the view
    update_view("devices_flat", version: 1, revert: 2)

    # Drop the linking table
    drop table(:devices_users)
  end
end
