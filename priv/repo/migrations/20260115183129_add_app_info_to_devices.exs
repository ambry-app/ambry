defmodule Ambry.Repo.Migrations.AddAppInfoToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :app_id, :string
      add :app_version, :string
      add :app_build, :string
    end
  end
end
