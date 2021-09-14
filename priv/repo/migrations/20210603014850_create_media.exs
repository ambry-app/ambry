defmodule Ambry.Repo.Migrations.CreateMedia do
  use Ecto.Migration

  def change do
    create table(:media) do
      timestamps()

      add :path, :text
      add :book_id, references(:books, on_delete: :nothing)
      add :narrator_id, references(:narrators, on_delete: :nothing)
    end

    create index(:media, [:book_id])
    create index(:media, [:narrator_id])
  end
end
