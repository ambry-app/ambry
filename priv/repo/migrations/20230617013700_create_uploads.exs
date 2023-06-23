defmodule Ambry.Repo.Migrations.CreateUploads do
  use Ecto.Migration

  def change do
    create table(:uploads) do
      timestamps()

      add :title, :text
      add :files, :json, null: false
      add :book_id, references(:books)
    end
  end
end
