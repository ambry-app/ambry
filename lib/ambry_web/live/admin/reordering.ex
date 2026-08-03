defmodule AmbryWeb.Admin.Reordering do
  @moduledoc """
  Moving an entry of an ordered `has_many` up or down in an admin form.

  Deliberately not drag-and-drop. Ordering a book's two authors is a
  once-in-a-while act on a list that is almost always two or three long, and
  a pair of buttons needs no JavaScript, works on a phone, and can be tested
  without a browser.

  ## Why this works on params rather than the changeset

  The obvious implementation — reorder the changeset's assoc list — does not
  work, and the reason is worth writing down.

  `cast_assoc`'s `:sort_param` really does order the incoming params (see
  `Ecto.Changeset.cast_params/4`), but `cast_relation` then throws the result
  away unless something actually changed: a pure reorder leaves every child
  changeset empty, `Relation.cast` returns `:ignore`, and the association ends
  up with no change at all. Reordering alone is invisible to Ecto.

  So the order has to be carried by a real field. Each row renders a hidden
  `position` input holding its rendered index; moving a row swaps two entries
  in the params, which swaps both their render order *and* their positions.
  Now the children genuinely differ, the cast keeps them in the new order, and
  `Ambry.Ecto.Positions` renumbers them 0..n on the way to the database.
  """

  import Ecto.Changeset

  @doc """
  Applies a `move` event's params to the form's params.

  Returns the updated params map, ready to rebuild a changeset with. Anything
  unrecognised returns the params untouched rather than raising: these values
  come off the wire, and the field name is only ever resolved against the
  schema's own associations, so a crafted event can't reach an arbitrary atom
  or an unrelated field.
  """
  def move(%Ecto.Changeset{} = changeset, params, %{
        "field" => field,
        "index" => index,
        "direction" => direction
      }) do
    with {:ok, association} <- association(changeset, field),
         {index, ""} <- Integer.parse(index),
         {:ok, offset} <- offset(direction) do
      swap(changeset, params, association, field, index, index + offset)
    else
      _unrecognized -> params
    end
  end

  def move(%Ecto.Changeset{}, params, _params), do: params

  defp swap(changeset, params, association, field, from, to) do
    entries = entries(changeset, params, field, get_assoc(changeset, association))
    keys = entries |> Map.keys() |> Enum.sort_by(&String.to_integer/1)

    with from_key when not is_nil(from_key) <- Enum.at(keys, from),
         to_key when not is_nil(to_key) <- Enum.at(keys, to),
         true <- to >= 0 do
      entries =
        entries
        |> Map.put(from_key, Map.fetch!(entries, to_key))
        |> Map.put(to_key, Map.fetch!(entries, from_key))
        |> renumber(keys)

      params
      |> Map.put(field, entries)
      |> Map.put(field <> "_sort", keys)
    else
      _out_of_range -> params
    end
  end

  # The position belongs to the slot, not to the row that's sitting in it.
  #
  # Letting it travel with the row is the subtle way to build buttons that do
  # nothing: every row would submit the position it already had, no child
  # changeset would differ, and `cast_relation` would discard the whole
  # association as unchanged — visibly reordered on screen, unchanged in the
  # database.
  defp renumber(entries, keys) do
    keys
    |> Enum.with_index()
    |> Enum.reduce(entries, fn {key, index}, entries ->
      Map.update!(entries, key, &Map.put(&1, "position", to_string(index)))
    end)
  end

  # What the form last submitted, or — before it has submitted anything — the
  # minimum that describes each existing row. Partial params are safe here:
  # `cast_assoc` only casts the keys it's given, so an untouched field keeps
  # its stored value.
  defp entries(_changeset, params, field, _assoc) when is_map_key(params, field) do
    Map.fetch!(params, field)
  end

  defp entries(_changeset, _params, _field, assoc) do
    assoc
    |> Enum.with_index()
    |> Map.new(fn {entry, index} ->
      {key(index), %{"id" => to_string(get_field(entry, :id)), "position" => to_string(index)}}
    end)
  end

  defp association(%Ecto.Changeset{data: %schema{}}, field) do
    Enum.find_value(schema.__schema__(:associations), :error, fn association ->
      if Atom.to_string(association) == field, do: {:ok, association}
    end)
  end

  defp offset("up"), do: {:ok, -1}
  defp offset("down"), do: {:ok, 1}
  defp offset(_other), do: :error

  defp key(index), do: to_string(index)
end
