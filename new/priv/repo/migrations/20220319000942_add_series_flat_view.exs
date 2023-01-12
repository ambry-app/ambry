defmodule Ambry.Repo.Migrations.AddSeriesFlatView do
  use Ecto.Migration
  use Familiar

  def change do
    create_view("series_flat", version: 1)
  end
end
