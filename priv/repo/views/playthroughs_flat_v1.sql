SELECT
  p.id,
  p.user_id,
  p.media_id,
  p.status,
  p.position,
  p.rate,
  p.started_at,
  p.last_event_at,
  m.duration AS media_duration,
  m.thumbnails -> 'small' AS media_thumbnail,
  b.title AS book_title,
  CASE
    WHEN m.duration > 0 AND p.position IS NOT NULL THEN
      ROUND((p.position / m.duration) * 100, 1)
    ELSE 0.0
  END AS progress_percent
FROM
  playthroughs_new AS p
  JOIN media AS m ON p.media_id = m.id
  JOIN books AS b ON m.book_id = b.id
ORDER BY
  p.last_event_at DESC
