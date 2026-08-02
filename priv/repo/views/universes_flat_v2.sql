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
    -- one cover per edition per book (a part set contributes its first
    -- part), unless a book's sole edition is a part set — then all its
    -- parts contribute. Mirrors part_set_stack_media/1; admin lists
    -- deliberately include non-ready media.
    SELECT
      media.thumbnails -> 'small'
    FROM
      books_universes AS book_universe
      INNER JOIN books AS book ON book.id = book_universe.book_id
      INNER JOIN media ON media.book_id = book.id
    WHERE
      book_universe.universe_id = universe.id
      AND media.thumbnails IS NOT NULL
      AND (
        media.recording_group_id IS NULL
        OR media.id = (
          SELECT m2.id
          FROM media m2
          WHERE m2.recording_group_id = media.recording_group_id
          ORDER BY m2.part_number ASC NULLS LAST, m2.id ASC
          LIMIT 1
        )
        OR (
          SELECT COUNT(DISTINCT m3.recording_group_id) = 1
            AND COUNT(*) FILTER (WHERE m3.recording_group_id IS NULL) = 0
          FROM media m3
          WHERE m3.book_id = media.book_id
        )
      )
    ORDER BY
      media.published DESC
  ) AS thumbnails,
  universe.inserted_at,
  universe.updated_at
FROM
  universes AS universe
ORDER BY
  universe.name
