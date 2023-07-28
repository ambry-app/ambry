defmodule Ambry.Repo.Migrations.FixAccidentalUserDeletion do
  use Ecto.Migration

  def up do
    drop constraint(:users, "users_loaded_player_state_id_fkey")

    alter table(:users) do
      modify :loaded_player_state_id, references(:player_states, on_delete: :nilify_all),
        null: true
    end
  end

  def down do
    drop constraint(:users, "users_loaded_player_state_id_fkey")

    alter table(:users) do
      modify :loaded_player_state_id, references(:player_states, on_delete: :delete_all),
        null: true
    end
  end
end
