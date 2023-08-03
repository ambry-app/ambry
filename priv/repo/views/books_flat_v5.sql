SELECT
  book.id,
  book.title,
  book.published,
  book.published_format,
  book.image_path,
  ARRAY(
    SELECT
      (author.name, person.name) :: person_name
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
  COUNT(media.id) AS media,
  book.description IS NOT NULL AS has_description,
  book.inserted_at,
  book.updated_at
FROM
  books AS book
  LEFT JOIN media ON book.id = media.book_id
GROUP BY
  book.id
ORDER BY
  book.title
