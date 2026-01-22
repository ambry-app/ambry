defmodule Ambry.Repo.Migrations.CreateDevicesFlatView do
  use Ecto.Migration

  use Familiar

  def up do
    create_view("devices_flat", version: 1)
  end

  def down do
    drop_view("devices_flat")
  end
end
