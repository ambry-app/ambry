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
      changeset
      |> detach(assoc)
      |> cast_assoc(assoc, opts)
      |> drop_stale_id(assoc, id_field)
    end
  end

  # A nested record is always a NEW record. `cast_assoc` on a loaded
  # `belongs_to` casts *onto the loaded one* when the params carry no id —
  # so a recording moved out of one set and into a set that doesn't exist yet
  # would have renamed the set it was leaving, taking every other member with
  # it. Which is the module's own rule, one step further: the record a row
  # points at is shared, and this form may not rewrite it.
  defp detach(changeset, assoc) do
    %{changeset | data: Map.put(changeset.data, assoc, nil)}
  end

  # Blanking the id is how a form says "I mean a record you don't have", and
  # Ecto refuses to write both: "cannot change belongs_to association because
  # there is already a change setting its foreign key to nil". The nested
  # record is the answer, and the id it lands under is Ecto's to fill in.
  defp drop_stale_id(changeset, assoc, id_field) do
    if get_change(changeset, assoc),
      do: delete_change(changeset, id_field),
      else: changeset
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
