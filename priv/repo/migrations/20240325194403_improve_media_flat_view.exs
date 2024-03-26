defmodule Ambry.Repo.Migrations.ImproveMediaFlatView do
  use Ecto.Migration
  use Familiar

  def change do
    execute "CREATE TYPE series_book AS (name text, number numeric)",
            "DROP TYPE series_book"

    update_view("media_flat", version: 3, revert: 2)
  end
end
