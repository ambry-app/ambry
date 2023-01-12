defmodule Ambry.Repo.Migrations.RemovePlayerStatesDuration do
  use Ecto.Migration

  def change do
    alter table(:player_states) do
      remove :duration
    end
  end
end
