defmodule Ambry.Repo.Migrations.AddUniverses do
  use Ecto.Migration

  def change do
    create table(:universes) do
      timestamps()

      add :name, :text
    end

    alter table(:books) do
      add :universe_id, references(:universes)
    end
  end
end
