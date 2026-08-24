defmodule Ambry.Ecto.EntityRef do
  @moduledoc """
  A join row that either points at a record or brings a new one with it.

  Every credit and membership on an edit form is a join row. Pointing is an
  id, which `cast_assoc` handles; naming something the library has never
  heard of is what this adds. The new record travels as nested params under
  the row, and the picker (`AmbryWeb.Components.EntityResolver`) posts the
  typed name straight into its name field.

  Nested params are ignored when the row is already linked: the record it
  points at is shared, so a form that cast it would be a form that could
  rewrite it. Nothing is created before the parent is saved.
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

  # A nested record is always a new one. `cast_assoc` on a loaded
  # `belongs_to` with no id in the params casts onto the loaded record, which
  # would rename the record the row is moving away from.
  defp detach(changeset, assoc) do
    %{changeset | data: Map.put(changeset.data, assoc, nil)}
  end

  # Ecto refuses a nested record and a nil foreign key in one changeset, and
  # the id the new record lands under is Ecto's to fill in anyway.
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
