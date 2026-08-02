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
    -- tile system v2 series rule: one cover per book, in series order —
    -- each book contributes its representative (the newest edition's
    -- first part / audiobook; all statuses on admin lists). Mirrors the
    -- Series-tile logic over Ambry.Media.Editions.
    SELECT
      rep.thumb
    FROM
      books_series AS series_book
      CROSS JOIN LATERAL (
        SELECT
          media.thumbnails -> 'small' AS thumb
        FROM
          media
        WHERE
          media.book_id = series_book.book_id
          AND (
            media.recording_group_id IS NULL
            OR media.id = (
              SELECT m2.id
              FROM media m2
              WHERE m2.recording_group_id = media.recording_group_id
              ORDER BY m2.part_number ASC NULLS LAST, m2.id ASC
              LIMIT 1
            )
          )
        ORDER BY
          media.published DESC NULLS LAST,
          media.id DESC
        LIMIT 1
      ) rep
    WHERE
      series_book.series_id = series.id
      AND rep.thumb IS NOT NULL
    ORDER BY
      series_book.book_number ASC
  ) AS thumbnails,
  ARRAY(
    SELECT
      DISTINCT (
        author.name,
        (
          SELECT
            STRING_AGG(person.name, ', ' ORDER BY author_link.id)
          FROM
            authors_people AS author_link
            INNER JOIN people AS person ON person.id = author_link.person_id
          WHERE
            author_link.author_id = author.id
        )
      ) :: person_name AS person_name
    FROM
      books_series AS series_book
      INNER JOIN books AS book ON book.id = series_book.book_id
      INNER JOIN authors_books AS authored_by ON book.id = authored_by.book_id
      INNER JOIN authors AS author ON author.id = authored_by.author_id
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
