defmodule Ambry.Repo.Migrations.FlatViewsEditionRules do
  use Ecto.Migration
  use Familiar

  # Tile system v2, admin side: list cover-stacks adopt the Edition rules —
  # one cover per edition (books view) / one cover per book, its newest
  # edition's representative (series & universes views). The sole-edition
  # exception is deleted; non-ready media stay visible (admin lists are ops
  # views). Mirrors Ambry.Media.Editions; parity-tested.

  def up do
    update_view("books_flat", version: 12)
    update_view("series_flat", version: 6)
    update_view("universes_flat", version: 3)
  end

  def down do
    update_view("books_flat", version: 11)
    update_view("series_flat", version: 5)
    update_view("universes_flat", version: 2)
  end
end
