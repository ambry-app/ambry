defmodule Ambry.Repo.Migrations.UpdateFlatViewsForThumbnails do
  use Ecto.Migration
  use Familiar

  def change do
    update_view("books_flat", version: 8, revert: 7)
    update_view("media_flat", version: 5, revert: 4)
    update_view("people_flat", version: 4, revert: 3)
    update_view("series_flat", version: 3, revert: 2)
  end
end
