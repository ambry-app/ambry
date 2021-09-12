defmodule Ambry.Repo.Migrations.FollowErd do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      modify :name, :text, null: false
    end

    alter table(:books) do
      modify :title, :text, null: false
      modify :published, :date, null: false

      remove :series_index
      remove :author_id
      remove :series_id
    end

    alter table(:media) do
      modify :path, :text, null: false

      remove :book_id
      remove :narrator_id
    end

    alter table(:media) do
      add :book_id, references(:books), null: false
    end

    create table(:authors_books) do
      add :author_id, references(:authors), null: false
      add :book_id, references(:books), null: false
    end

    create unique_index(:authors_books, [:author_id, :book_id])

    create table(:books_series) do
      add :book_id, references(:books), null: false
      add :series_id, references(:series), null: false
      add :book_number, :decimal, null: false
    end

    create unique_index(:books_series, [:book_id, :series_id])

    create table(:media_narrators) do
      add :media_id, references(:media), null: false
      add :narrator_id, references(:narrators), null: false
    end

    create unique_index(:media_narrators, [:media_id, :narrator_id])
  end
end
