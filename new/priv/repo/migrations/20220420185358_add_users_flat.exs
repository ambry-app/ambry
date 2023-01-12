defmodule Ambry.Repo.Migrations.AddUsersFlat do
  use Ecto.Migration
  use Familiar

  def change do
    create_view("users_flat", version: 1)
  end
end
