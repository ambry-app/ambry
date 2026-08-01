defmodule Ambry.Repo.Migrations.CreateMetadataCache do
  use Ecto.Migration

  def change do
    create table(:metadata_cache, primary_key: false) do
      add :key, :text, primary_key: true
      add :value, :binary, null: false
      add :cached_at, :utc_datetime, null: false
    end
  end
end
