SELECT
  person.id,
  person.name,
  ARRAY(
    SELECT
      author.name
    FROM
      authors_people AS author_link
      INNER JOIN authors AS author ON author.id = author_link.author_id
    WHERE
      author_link.person_id = person.id
  ) AS writing_as,
  ARRAY(
    SELECT
      narrator.name
    FROM
      narrators AS narrator
    WHERE
      narrator.person_id = person.id
  ) AS narrating_as,
  COUNT(author.id) > 0 AS is_author,
  COUNT(distinct authored_book.id) AS authored_books,
  COUNT(narrator.id) > 0 AS is_narrator,
  COUNT(distinct narrated_media.id) AS narrated_media,
  person.thumbnails -> 'small' AS thumbnail,
  person.description IS NOT NULL AS has_description,
  person.inserted_at,
  person.updated_at
FROM
  people AS person
  LEFT JOIN authors_people AS author_link ON person.id = author_link.person_id
  LEFT JOIN authors AS author ON author.id = author_link.author_id
  LEFT JOIN narrators AS narrator ON person.id = narrator.person_id
  LEFT JOIN authors_books AS authored_book ON author.id = authored_book.author_id
  LEFT JOIN media_narrators AS narrated_media ON narrator.id = narrated_media.narrator_id
GROUP BY
  person.id
ORDER BY
  person.name
