defmodule Ambry.Repo.Migrations.FixBooksFlat do
  use Ecto.Migration
  use Familiar

  def change do
    replace_view("books_flat", version: 3, revert: 2)
  end
end
