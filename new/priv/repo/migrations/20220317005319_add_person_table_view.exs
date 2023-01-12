defmodule Ambry.Repo.Migrations.AddPersonTableView do
  use Ecto.Migration
  use Familiar

  def change do
    create_view("people_flat", version: 1)
  end
end
