defmodule Ambry.Repo.Migrations.BooksFlatDescription do
  use Ecto.Migration
  use Familiar

  def change do
    update_view("books_flat", version: 5, revert: 4)
  end
end
