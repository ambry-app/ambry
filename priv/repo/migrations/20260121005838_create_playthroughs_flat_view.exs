defmodule Ambry.Repo.Migrations.CreatePlaythroughsFlatView do
  use Ecto.Migration

  use Familiar

  def up do
    create_view("playthroughs_flat", version: 1)
  end

  def down do
    drop_view("playthroughs_flat")
  end
end
