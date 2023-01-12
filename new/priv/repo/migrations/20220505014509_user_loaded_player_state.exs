defmodule Ambry.Repo.Migrations.UserLoadedPlayerState do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :loaded_player_state_id, references(:player_states, on_delete: :delete_all), null: true
    end
  end
end
