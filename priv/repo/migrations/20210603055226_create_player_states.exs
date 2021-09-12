defmodule Ambry.Repo.Migrations.CreatePlayerStates do
  use Ecto.Migration

  def change do
    create table(:player_states) do
      add :position, :decimal
      add :playback_rate, :decimal
      add :media_id, references(:media, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:player_states, [:media_id])
    create index(:player_states, [:user_id])
  end
end
