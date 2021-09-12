defmodule Ambry.Repo.Migrations.CreateSeries do
  use Ecto.Migration

  def change do
    create table(:series) do
      add :name, :text

      timestamps()
    end
  end
end
