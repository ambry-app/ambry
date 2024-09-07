SELECT
  book.id,
  book.title,
  book.published,
  book.published_format,
  ARRAY(
    SELECT
      media.image_path
    FROM
      media
    WHERE
      media.book_id = book.id
      AND media.image_path IS NOT NULL
    ORDER BY
      media.published DESC
  ) AS image_paths,
  ARRAY(
    SELECT
      (author.name, person.name) :: person_name
    FROM
      authors_books AS authored_by
      INNER JOIN authors AS author ON author.id = authored_by.author_id
      INNER JOIN people AS person ON person.id = author.person_id
    WHERE
      authored_by.book_id = book.id
    ORDER BY
      author.name
  ) AS authors,
  ARRAY(
    SELECT
      (series.name, books_series.book_number) :: series_book
    FROM
      books_series
      INNER JOIN series ON series.id = books_series.series_id
    WHERE
      books_series.book_id = book.id
    ORDER BY
      books_series.book_number ASC
  ) AS series,
  (
    SELECT
      universe.name
    FROM
      universes AS universe
    WHERE
      universe.id = book.universe_id
  ) AS universe,
  (
    SELECT
      COUNT(media.id)
    FROM
      media
    WHERE
      media.book_id = book.id
  ) AS media,
  book.inserted_at,
  book.updated_at,
  -- deprecated
  book.image_path,
  book.description IS NOT NULL AS has_description
FROM
  books AS book
ORDER BY
  book.title
