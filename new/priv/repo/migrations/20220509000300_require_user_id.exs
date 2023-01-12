defmodule Ambry.Repo.Migrations.RequireUserId do
  use Ecto.Migration
  use Familiar

  def up do
    wrapper(fn ->
      alter table(:player_states) do
        modify :user_id, references(:users, on_delete: :delete_all), null: false
      end
    end)
  end

  def down do
    wrapper(fn ->
      alter table(:player_states) do
        modify :user_id, references(:users, on_delete: :delete_all)
      end
    end)
  end

  defp wrapper(fun) do
    drop_view("users_flat")

    drop constraint(:player_states, "player_states_user_id_fkey")

    fun.()

    create_view("users_flat", version: 1)
  end
end
