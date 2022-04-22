defmodule Ambry.Repo.Migrations.AddMediaToBooksFlat do
  use Ecto.Migration
  use Familiar

  def change do
    update_view("books_flat", version: 2, revert: 1)
  end
end
