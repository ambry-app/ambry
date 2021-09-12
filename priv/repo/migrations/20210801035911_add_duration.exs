defmodule Ambry.Repo.Migrations.AddDuration do
  use Ecto.Migration

  def change do
    alter table(:player_states) do
      add :duration, :decimal
    end
  end
end
