defmodule Ambry.Repo.Migrations.AddUsersFlat do
  use Ecto.Migration

  def up do
    execute """
    CREATE VIEW users_flat AS
    SELECT
      users.id,
      users.email,
      users.admin,
      CASE
        WHEN users.confirmed_at IS NOT NULL THEN true
        ELSE false
      END confirmed,
      COUNT(player_states.id) FILTER (WHERE player_states.status = 'in_progress') AS media_in_progress,
      COUNT(player_states.id) FILTER (WHERE player_states.status = 'finished') AS media_finished,
      (
        SELECT
          inserted_at
        FROM
          users_tokens
        WHERE
          user_id = users.id
        ORDER BY
          inserted_at DESC
        LIMIT 1
      ) AS last_login_at,
      users.inserted_at,
      users.updated_at
    FROM
      users
      LEFT JOIN player_states ON users.id = player_states.user_id
    GROUP BY
      users.id
    ORDER BY
      users.email;
    """
  end

  def down do
    execute "DROP VIEW users_flat;"
  end
end
