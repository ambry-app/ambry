defmodule Ambry.Repo.Migrations.CreateBooks do
  use Ecto.Migration

  def change do
    create table(:books) do
      add :title, :string

      timestamps()
    end
  end
end
