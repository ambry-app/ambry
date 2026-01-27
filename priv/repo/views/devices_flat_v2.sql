SELECT
  d.id,
  du.user_id,
  d.type,
  d.brand,
  d.model_name,
  d.browser,
  d.browser_version,
  d.os_name,
  d.os_version,
  d.app_id,
  d.app_version,
  d.app_build,
  du.last_seen_at,
  d.inserted_at,
  d.updated_at,
  COUNT(e.id) AS event_count
FROM
  devices AS d
  JOIN devices_users AS du ON d.id = du.device_id
  LEFT JOIN playthroughs_new AS pn ON pn.user_id = du.user_id
  LEFT JOIN playback_events AS e ON e.device_id = d.id AND e.playthrough_id = pn.id
GROUP BY
  d.id, du.user_id, du.last_seen_at
ORDER BY
  du.last_seen_at DESC NULLS LAST
