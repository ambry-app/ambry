defmodule Ambry.Repo.Migrations.CreateGoodreadsCache do
  use Ecto.Migration

  def change do
    create table(:goodreads_cache, primary_key: false) do
      add :key, :text, primary_key: true
      add :value, :binary, null: false

      timestamps(updated_at: false)
    end
  end
end
