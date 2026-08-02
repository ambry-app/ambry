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
    -- tile system v2: one cover per book — its newest edition's
    -- representative (all statuses on admin lists). Universe membership is
    -- unnumbered, so books order by title.
    SELECT
      rep.thumb
    FROM
      books_universes AS book_universe
      INNER JOIN books AS book ON book.id = book_universe.book_id
      CROSS JOIN LATERAL (
        SELECT
          media.thumbnails -> 'small' AS thumb
        FROM
          media
        WHERE
          media.book_id = book.id
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
      book_universe.universe_id = universe.id
      AND rep.thumb IS NOT NULL
    ORDER BY
      book.title ASC
  ) AS thumbnails,
  universe.inserted_at,
  universe.updated_at
FROM
  universes AS universe
ORDER BY
  universe.name
