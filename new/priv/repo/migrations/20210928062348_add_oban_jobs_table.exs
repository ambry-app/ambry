defmodule Ambry.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(version: 10)
  end

  def down do
    Oban.Migrations.down(version: 1)
  end
end
