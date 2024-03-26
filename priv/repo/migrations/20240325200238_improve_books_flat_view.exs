defmodule Ambry.Repo.Migrations.ImproveBooksFlatView do
  use Ecto.Migration
  use Familiar

  def change do
    update_view("books_flat", version: 6, revert: 5)
  end
end
