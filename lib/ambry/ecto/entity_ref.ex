defmodule Ambry.Ecto.EntityRef do
  @moduledoc """
  A row that either points at a record or brings a new one with it.

  Every credit and membership on an edit form is a join row: a book's authors,
  an audiobook's narrators, a book's series and universes. Pointing is an id
  (`author_id`), which `cast_assoc` has always handled; what these forms could
  not do was *name* something the library has never heard of, so crediting a
  new author meant leaving the form, making them by hand, and coming back.

  The new record travels as nested params under the row — `cast_assoc` all
  the way down, no substitution anywhere — and the picker
  (`AmbryWeb.Components.EntityResolver`) posts the typed name straight into
  the nested record's own name field. `Ambry.People.AuthorPerson` has always
  worked this way; this is the same idiom, given to every other join.

  ## Only when nothing was picked

  The picker's text box keeps what was typed even after a record is chosen, so
  nested params arrive on rows that are perfectly well linked. `cast_new/4`
  ignores them: a row with an id is a row that points at something, and the
  record it points at is **shared** — a person credited on forty books — so a
  form that cast it would be a form that could rewrite it.

  Nothing is created before the parent is saved: the nested changeset is
  inserted by the same `Repo.insert`/`update` that saves the row, or by
  neither.
  """

  import Ecto.Changeset

  @doc """
  Casts the nested record a row brings, unless the row points at one already.
  """
  def cast_new(changeset, assoc, id_field, opts \\ []) do
    if linked?(changeset, id_field) do
      changeset
    else
      cast_assoc(changeset, assoc, opts)
    end
  end

  @doc """
  Requires the row to point at a record or to bring one.

  The error lands on the id, which is where the picker renders it.
  """
  def validate_linked_or_new(changeset, id_field, assoc) do
    if linked?(changeset, id_field) or get_change(changeset, assoc) do
      changeset
    else
      add_error(changeset, id_field, "can't be blank")
    end
  end

  defp linked?(changeset, id_field) do
    case get_field(changeset, id_field) do
      nil -> false
      "" -> false
      _id -> true
    end
  end
end
