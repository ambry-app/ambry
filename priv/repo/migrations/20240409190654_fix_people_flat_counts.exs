defmodule Ambry.Repo.Migrations.FixPeopleFlatCounts do
  use Ecto.Migration
  use Familiar

  def change do
    update_view("people_flat", version: 3, revert: 2)
  end
end
