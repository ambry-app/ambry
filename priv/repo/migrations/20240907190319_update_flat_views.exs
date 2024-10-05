defmodule Ambry.Repo.Migrations.UpdateFlatViews do
  use Ecto.Migration
  use Familiar

  def change do
    update_view("books_flat", version: 7, revert: 6)
    update_view("media_flat", version: 4, revert: 3)
    update_view("series_flat", version: 2, revert: 1)
  end
end
