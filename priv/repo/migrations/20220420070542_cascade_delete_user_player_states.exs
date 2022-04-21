defmodule Ambry.Repo.Migrations.CascadeDeleteUserPlayerStates do
  use Ecto.Migration

  def up do
    drop constraint(:player_states, "player_states_user_id_fkey")

    alter table(:player_states) do
      modify :user_id, references(:users, on_delete: :delete_all)
    end
  end

  def down do
    drop constraint(:player_states, "player_states_user_id_fkey")

    alter table(:player_states) do
      modify :user_id, references(:users)
    end
  end
end
