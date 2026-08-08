defmodule Ambry.Repo.Migrations.EnableUnaccent do
  use Ecto.Migration

  # The SQL twin of AutoMatch.person_key/1 needs to fold accents the way the
  # Elixir side does: the library's "Patricia Rodríguez" and a file's
  # "Patricia Rodriguez" are one narrator, and without this the credit
  # created a second person of the same name in different spelling.
  def up do
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS unaccent")
  end
end
