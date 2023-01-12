defmodule Ambry.Repo.Migrations.BookIdOnUpload do
  use Ecto.Migration

  def change do
    alter table(:uploads) do
      add :book_id, references(:books), null: false
    end
  end
end
