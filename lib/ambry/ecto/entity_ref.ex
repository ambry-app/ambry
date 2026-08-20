defmodule Ambry.Ecto.EntityRef do
  @moduledoc """
  A row that points at a record the library may not have yet.

  Every credit and membership on an edit form is a join row carrying an id —
  a book's authors, an audiobook's narrators, a book's series and universes.
  Until now the id was the only answer those rows could give, so a form could
  attach a person the library already had and nothing else: crediting a
  narrator who was new meant leaving the form, making them by hand, and
  coming back. The import form has never had that limit, and closing the gap
  is what `EDIT_PARITY_PLAN.md` is about.

  So a row may answer with a **name** instead. The picker
  (`AmbryWeb.Components.EntityResolver`) has always been able to offer
  "Create …" — the edit forms simply had it switched off — and it posts the
  typed name in a second input beside the id.

  ## The name is resolved at save, not while typing

  Nothing is created until the form is submitted. The changeset accepts a row
  that names something instead of pointing at it, and the LiveView turns
  those names into records in its submit handler, one transaction later.

  That is deliberate: creating on the keystroke, or during a `phx-change`,
  would litter the library with people invented by a change of mind, and
  creating inside a changeset would make casting a form write to the
  database. The cost is that a name must be resolved before the row can be
  inserted, which is why the resolution lives in one place per form and is
  tested there.
  """

  import Ecto.Changeset

  @doc """
  Requires the row to either point at a record or name one.

  The error lands on the id, which is where the picker renders it.
  """
  def validate_linked_or_named(changeset, id_field, name_field) do
    if blank?(get_field(changeset, id_field)) and blank?(get_field(changeset, name_field)) do
      add_error(changeset, id_field, "can't be blank")
    else
      changeset
    end
  end

  @doc """
  Fills in the ids of rows that named a record, creating what is missing.

  Takes the rows a form posted for one association and the function that
  turns a name into a record, and answers the same rows with ids in them. A
  row that already points at something is left exactly as it is — including
  one whose name box still holds the text the operator typed before picking,
  which the picker leaves behind on purpose.
  """
  def resolve(params, assoc, id_key, name_key, create) when is_map(params) do
    case Map.get(params, assoc) do
      rows when is_map(rows) ->
        Map.put(
          params,
          assoc,
          Map.new(rows, fn {key, row} -> {key, resolve_row(row, id_key, name_key, create)} end)
        )

      rows when is_list(rows) ->
        Map.put(params, assoc, Enum.map(rows, &resolve_row(&1, id_key, name_key, create)))

      _absent ->
        params
    end
  end

  defp resolve_row(row, id_key, name_key, create) when is_map(row) do
    name = row |> Map.get(name_key) |> presence()

    if blank?(Map.get(row, id_key)) and name do
      Map.put(row, id_key, to_string(create.(name).id))
    else
      row
    end
  end

  defp resolve_row(row, _id_key, _name_key, _create), do: row

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp presence(value), do: if(!blank?(value), do: String.trim(value))
end
