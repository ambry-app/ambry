SELECT
  universe.id,
  universe.name,
  (
    SELECT
      COUNT(books_universes.id)
    FROM
      books_universes
    WHERE
      books_universes.universe_id = universe.id
  ) AS books,
  ARRAY(
    SELECT
      media.thumbnails -> 'small'
    FROM
      books_universes AS book_universe
      INNER JOIN books AS book ON book.id = book_universe.book_id
      INNER JOIN media ON media.book_id = book.id
    WHERE
      book_universe.universe_id = universe.id
      AND media.thumbnails IS NOT NULL
    ORDER BY
      media.published DESC
  ) AS thumbnails,
  universe.inserted_at,
  universe.updated_at
FROM
  universes AS universe
ORDER BY
  universe.name
