defmodule Ambry.Repo.Migrations.BooksDatamodelOverhaul do
  use Ecto.Migration

  def change do
    alter table(:media) do
      add :image_path, :text
      add :description, :text
      add :publisher, :text
    end
  end
end
