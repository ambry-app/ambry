defmodule Ambry.Repo.Migrations.FlatViewsByCreditPosition do
  use Ecto.Migration
  use Familiar

  # The flat views built their author, narrator and series arrays in
  # alphabetical order (and a book's series list in book-number order, which
  # across two different series means nothing at all). Now that credits carry
  # an explicit position, the views follow the operator's ordering instead —
  # so the first author really is the primary one everywhere a book or
  # recording is rendered.
  #
  # `series_flat` and `people_flat` are deliberately untouched: a series' list
  # of authors is a DISTINCT set gathered across every book in it, so no one
  # book's ordering owns it, and `people_flat` doesn't build an ordered credit
  # array at all.

  def up do
    update_view("books_flat", version: 13)
    update_view("media_flat", version: 12)
  end

  def down do
    update_view("books_flat", version: 12)
    update_view("media_flat", version: 11)
  end
end
