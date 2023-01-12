defmodule Ambry.Repo.Migrations.CreateNarrators do
  use Ecto.Migration

  def change do
    create table(:narrators) do
      timestamps()

      add :name, :text
    end
  end
end
