defmodule Ambry.Repo.Migrations.CreateMetadataProviderConfigs do
  use Ecto.Migration

  def change do
    create table(:metadata_provider_configs, primary_key: false) do
      add :provider_id, :text, primary_key: true
      add :enabled, :boolean, null: false, default: true
      add :priority, :integer
      add :config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end
  end
end
