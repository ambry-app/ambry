defmodule Ambry.Repo.Migrations.FlatViewStackTileRules do
  use Ecto.Migration
  use Familiar

  # Admin books/series/universes list cover-stacks now follow the same
  # part-set rules as the user-facing tiles (one cover per edition — a part
  # set contributes its first part — sole-edition sets stack their parts),
  # while deliberately keeping non-ready media visible (admin lists are ops
  # views). v1.9.0 punch list.

  def up do
    update_view("books_flat", version: 11)
    update_view("series_flat", version: 5)
    update_view("universes_flat", version: 2)
  end

  def down do
    update_view("books_flat", version: 10)
    update_view("series_flat", version: 4)
    update_view("universes_flat", version: 1)
  end
end
