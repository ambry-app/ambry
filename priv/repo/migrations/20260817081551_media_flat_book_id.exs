defmodule Ambry.Repo.Migrations.MediaFlatBookId do
  use Ecto.Migration
  use Familiar

  # A flat view of media that can't be filtered by its book was missing a
  # column. The set-member picker needs exactly that — a set holds its own
  # book's recordings and nothing else — and without it the admin had two
  # builders for "a recording as a picker option", one reading the view and
  # one reading the table, free to disagree about how a recording describes
  # itself.
  def up, do: update_view("media_flat", version: 16)
  def down, do: update_view("media_flat", version: 15)
end
