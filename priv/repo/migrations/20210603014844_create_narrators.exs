defmodule Ambry.Repo.Migrations.CreateNarrators do
  use Ecto.Migration

  def change do
    create table(:narrators) do
      add :name, :text

      timestamps()
    end
  end
end
