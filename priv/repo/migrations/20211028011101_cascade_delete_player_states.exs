defmodule Ambry.Repo.Migrations.CascadeDeletePlayerStates do
  use Ecto.Migration

  def up do
    drop constraint(:player_states, "player_states_media_id_fkey")

    alter table(:player_states) do
      modify :media_id, references(:media, on_delete: :delete_all)
    end

    drop constraint(:media_narrators, "media_narrators_media_id_fkey")

    alter table(:media_narrators) do
      modify :media_id, references(:media, on_delete: :delete_all)
    end
  end

  def down do
    drop constraint(:player_states, "player_states_media_id_fkey")

    alter table(:player_states) do
      modify :media_id, references(:media)
    end

    drop constraint(:media_narrators, "media_narrators_media_id_fkey")

    alter table(:media_narrators) do
      modify :media_id, references(:media)
    end
  end
end
