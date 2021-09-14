defmodule Ambry.Repo.Migrations.CreateAuthors do
  use Ecto.Migration

  def change do
    create table(:authors) do
      timestamps()

      add :name, :text
    end
  end
end
