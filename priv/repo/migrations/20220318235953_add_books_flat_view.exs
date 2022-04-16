defmodule Ambry.Repo.Migrations.AddBooksFlatView do
  use Ecto.Migration

  def up do
    execute """
    CREATE TYPE person_name AS (name text, person_name text);
    """

    execute """
    CREATE VIEW books_flat AS
    SELECT
      book.id,
      book.title,
      book.published,
      book.image_path,
      ARRAY(
        SELECT
          (author.name, person.name):: person_name
        FROM
          authors_books AS authored_by
          INNER JOIN authors AS author ON author.id = authored_by.author_id
          INNER JOIN people AS person ON person.id = author.person_id
        WHERE
          authored_by.book_id = book.id
      ) AS authors,
      ARRAY(
        SELECT
          series.name
        FROM
          books_series
          INNER JOIN series ON series.id = books_series.series_id
        WHERE
          books_series.book_id = book.id
      ) AS series,
      (
        SELECT
          universe.name
        FROM
          universes AS universe
        WHERE
          universe.id = book.universe_id
      ) AS universe,
      book.inserted_at,
      book.updated_at
    FROM
      books AS book
    ORDER BY
      book.title;
    """
  end

  def down do
    execute "DROP VIEW books_flat;"
    execute "DROP TYPE person_name;"
  end
end
