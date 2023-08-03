defmodule Ambry.Repo.Migrations.PeopleFlatDescription do
  use Ecto.Migration
  use Familiar

  def change do
    update_view("people_flat", version: 2, revert: 1)
  end
end
