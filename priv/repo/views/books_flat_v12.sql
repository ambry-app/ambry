SELECT
  book.id,
  book.title,
  book.published,
  book.published_format,
  ARRAY(
    -- tile system v2: one cover per edition — a part set contributes its
    -- first part — newest edition first. Mirrors Ambry.Media.Editions
    -- (all_statuses: admin lists deliberately include non-ready media);
    -- held in lockstep by test/ambry/flat_view_stack_test.exs.
    SELECT
      media.thumbnails -> 'small'
    FROM
      media
    WHERE
      media.book_id = book.id
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
      )
    ORDER BY
      media.published DESC NULLS LAST,
      media.id DESC
  ) AS thumbnails,
  ARRAY(
    SELECT
      (
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
      ) :: person_name
    FROM
      authors_books AS authored_by
      INNER JOIN authors AS author ON author.id = authored_by.author_id
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
      STRING_AGG(universe.name, ', ' ORDER BY universe.name)
    FROM
      books_universes AS book_universe
      INNER JOIN universes AS universe ON universe.id = book_universe.universe_id
    WHERE
      book_universe.book_id = book.id
  ) AS universes,
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
