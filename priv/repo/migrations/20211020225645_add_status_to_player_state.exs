defmodule Ambry.Repo.Migrations.AddStatusToPlayerState do
  use Ecto.Migration

  def change do
    alter table(:player_states) do
      add :status, :text, null: false, default: "in_progress"
    end
  end
end
