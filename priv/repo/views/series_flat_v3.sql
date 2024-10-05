SELECT
  series.id,
  series.name,
  (
    SELECT
      COUNT(books_series.id)
    FROM
      books_series
    WHERE
      books_series.series_id = series.id
  ) AS books,
  (
    SELECT
      COUNT(media.id)
    FROM
      books_series AS series_book
      INNER JOIN books AS book ON book.id = series_book.book_id
      INNER JOIN media ON media.book_id = book.id
    WHERE
      series_book.series_id = series.id
  ) AS media,
  ARRAY(
    SELECT
      media.thumbnails -> 'small'
    FROM
      books_series AS series_book
      INNER JOIN books AS book ON book.id = series_book.book_id
      INNER JOIN media ON media.book_id = book.id
    WHERE
      series_book.series_id = series.id
      AND media.thumbnails IS NOT NULL
    ORDER BY
      media.published DESC
  ) AS thumbnails,
  ARRAY(
    SELECT
      DISTINCT (author.name, person.name) :: person_name AS person_name
    FROM
      books_series AS series_book
      INNER JOIN books AS book ON book.id = series_book.book_id
      INNER JOIN authors_books AS authored_by ON book.id = authored_by.book_id
      INNER JOIN authors AS author ON author.id = authored_by.author_id
      INNER JOIN people AS person ON person.id = author.person_id
    WHERE
      series_book.series_id = series.id
    ORDER BY
      person_name
  ) AS authors,
  series.inserted_at,
  series.updated_at
FROM
  series
ORDER BY
  series.name
