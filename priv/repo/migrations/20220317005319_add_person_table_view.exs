defmodule Ambry.Repo.Migrations.AddPersonTableView do
  use Ecto.Migration

  def up do
    execute """
    CREATE VIEW people_flat AS
    SELECT
      person.id,
      person.name,
      person.image_path,
      COUNT(author.id) > 0 AS is_author,
      ARRAY_REMOVE(ARRAY_AGG(DISTINCT author.name), NULL) AS authors,
      COUNT(authored_book.id) AS authored_books,
      COUNT(narrator.id) > 0 AS is_narrator,
      ARRAY_REMOVE(ARRAY_AGG(DISTINCT narrator.name), NULL) AS narrators,
      COUNT(narrated_media.id) AS narrated_media,
      person.inserted_at,
      person.updated_at
    FROM
      people AS person
      LEFT JOIN authors AS author ON person.id = author.person_id
      LEFT JOIN narrators AS narrator ON person.id = narrator.person_id
      LEFT JOIN authors_books AS authored_book ON author.id = authored_book.author_id
      LEFT JOIN media_narrators AS narrated_media ON narrator.id = narrated_media.narrator_id
    GROUP BY
      person.id
    ORDER BY
      person.name;
    """
  end

  def down do
    execute "DROP VIEW people_flat;"
  end
end
