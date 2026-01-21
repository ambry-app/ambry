SELECT
  d.id,
  d.user_id,
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
  d.last_seen_at,
  d.inserted_at,
  d.updated_at,
  COUNT(e.id) AS event_count
FROM
  devices AS d
  LEFT JOIN playback_events AS e ON d.id = e.device_id
GROUP BY
  d.id
ORDER BY
  d.last_seen_at DESC NULLS LAST
