SELECT
  users.id,
  users.email,
  users.admin,
  CASE
    WHEN users.confirmed_at IS NOT NULL THEN true
    ELSE false
  END confirmed,
  COUNT(DISTINCT playthroughs_new.media_id) FILTER (
    WHERE
      playthroughs_new.status = 'in_progress'
  ) AS media_in_progress,
  COUNT(DISTINCT playthroughs_new.media_id) FILTER (
    WHERE
      playthroughs_new.status = 'finished'
  ) AS media_finished,
  (
    SELECT
      inserted_at
    FROM
      users_tokens
    WHERE
      user_id = users.id
    ORDER BY
      inserted_at DESC
    LIMIT
      1
  ) AS last_login_at,
  users.inserted_at,
  users.updated_at
FROM
  users
  LEFT JOIN playthroughs_new ON users.id = playthroughs_new.user_id
GROUP BY
  users.id
ORDER BY
  users.email
