defmodule Ambry.Repo.Migrations.FixDuplicatePlayerStates do
  use Ecto.Migration

  def up do
    # deletes older player_states with duplicate media_id
    execute """
    DELETE FROM
      player_states ps
    WHERE
      EXISTS (
        SELECT
          *
        FROM
          player_states x
        WHERE
          x.media_id = ps.media_id
          AND x.ctid > ps.ctid
      );
    """

    create unique_index(:player_states, [:user_id, :media_id])
  end

  def down do
    drop unique_index(:player_states, [:user_id, :media_id])
  end
end
