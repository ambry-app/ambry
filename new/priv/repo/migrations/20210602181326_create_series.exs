defmodule Ambry.Repo.Migrations.CreateSeries do
  use Ecto.Migration

  def change do
    create table(:series) do
      timestamps()

      add :name, :text
    end
  end
end
