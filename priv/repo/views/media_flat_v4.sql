SELECT
  media.id,
  media.status,
  media.full_cast,
  media.abridged,
  media.duration,
  media.published,
  media.published_format,
  media.publisher,
  media.image_path,
  CASE
    WHEN media.chapters IS NOT NULL THEN JSONB_ARRAY_LENGTH(media.chapters)
    ELSE 0
  END chapters,
  book.title AS book,
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
      (narrator.name, person.name) :: person_name
    FROM
      media_narrators AS narrated_by
      INNER JOIN narrators AS narrator ON narrator.id = narrated_by.narrator_id
      INNER JOIN people AS person ON person.id = narrator.person_id
    WHERE
      narrated_by.media_id = media.id
    ORDER BY
      narrator.name
  ) AS narrators,
  media.description IS NOT NULL AS has_description,
  media.inserted_at,
  media.updated_at
FROM
  media
  INNER JOIN books AS book ON book.id = media.book_id
ORDER BY
  book
