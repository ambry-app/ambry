defmodule Ambry.Repo.Migrations.AddPeople do
  use Ecto.Migration

  def change do
    create table(:people) do
      timestamps()

      add :name, :text
      add :image_path, :text
      add :description, :text
    end

    alter table(:authors) do
      remove :image_path
      remove :description

      add :person_id, references(:people)
    end

    alter table(:narrators) do
      remove :image_path
      remove :description

      add :person_id, references(:people)
    end
  end
end
