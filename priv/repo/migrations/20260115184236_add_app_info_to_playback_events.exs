defmodule Ambry.Repo.Migrations.AddAppInfoToPlaybackEvents do
  use Ecto.Migration

  def up do
    alter table(:playback_events) do
      add :app_version, :string
      add :app_build, :string
    end

    # Backfill existing events from their device's current app info
    execute("""
    UPDATE playback_events pe
    SET app_version = d.app_version,
        app_build = d.app_build
    FROM devices d
    WHERE pe.device_id = d.id
      AND (d.app_version IS NOT NULL OR d.app_build IS NOT NULL)
    """)
  end

  def down do
    alter table(:playback_events) do
      remove :app_version
      remove :app_build
    end
  end
end
