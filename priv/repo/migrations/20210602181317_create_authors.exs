defmodule Ambry.Repo.Migrations.CreateAuthors do
  use Ecto.Migration

  def change do
    create table(:authors) do
      add :name, :text

      timestamps()
    end
  end
end
