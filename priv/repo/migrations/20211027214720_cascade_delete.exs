defmodule Ambry.Repo.Migrations.CascadeDelete do
  use Ecto.Migration

  def up do
    drop constraint(:authors, "authors_person_id_fkey")

    alter table(:authors) do
      modify :person_id, references(:people, on_delete: :delete_all)
    end

    drop constraint(:narrators, "narrators_person_id_fkey")

    alter table(:narrators) do
      modify :person_id, references(:people, on_delete: :delete_all)
    end

    drop constraint(:authors_books, "authors_books_book_id_fkey")

    alter table(:authors_books) do
      modify :book_id, references(:books, on_delete: :delete_all)
    end

    drop constraint(:books_series, "books_series_book_id_fkey")
    drop constraint(:books_series, "books_series_series_id_fkey")

    alter table(:books_series) do
      modify :book_id, references(:books, on_delete: :delete_all)
      modify :series_id, references(:series, on_delete: :delete_all)
    end
  end

  def down do
    drop constraint(:authors, "authors_person_id_fkey")

    alter table(:authors) do
      modify :person_id, references(:people)
    end

    drop constraint(:narrators, "narrators_person_id_fkey")

    alter table(:narrators) do
      modify :person_id, references(:people)
    end

    drop constraint(:authors_books, "authors_books_book_id_fkey")

    alter table(:authors_books) do
      modify :book_id, references(:books)
    end

    drop constraint(:books_series, "books_series_book_id_fkey")
    drop constraint(:books_series, "books_series_series_id_fkey")

    alter table(:books_series) do
      modify :book_id, references(:books)
      modify :series_id, references(:series)
    end
  end
end
