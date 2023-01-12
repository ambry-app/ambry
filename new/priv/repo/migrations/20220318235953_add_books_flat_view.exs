defmodule Ambry.Repo.Migrations.AddBooksFlatView do
  use Ecto.Migration

  use Familiar

  def up do
    execute """
    CREATE TYPE person_name AS (name text, person_name text);
    """

    create_view("books_flat", version: 1)
  end

  def down do
    drop_view("books_flat")

    execute "DROP TYPE person_name;"
  end
end
