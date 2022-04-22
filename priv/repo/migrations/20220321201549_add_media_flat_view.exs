defmodule Ambry.Repo.Migrations.AddMediaFlatView do
  use Ecto.Migration
  use Familiar

  def change do
    create_view("media_flat", version: 1)
  end
end
