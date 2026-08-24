defmodule Ambry.Ecto.Positions do
  @moduledoc """
  Numbers an ordered `has_many` by where each entry sits in the list.

  Phoenix's `sort_param` reorders the changesets but writes nothing down, so
  the order wouldn't survive the round trip without this.

  Entries on their way out keep their place in the list and don't consume a
  number: the list *is* the instruction to Ecto, and dropping one would fire
  `on_replace: :delete` on something the operator never removed.
  """

  import Ecto.Changeset

  @doc """
  Numbers the entries of `field` by their position in the list.
  """
  def put_positions(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      entries ->
        # Straight into `changes`, not `put_change/3`: Ecto refuses to run
        # relation-change tracking over its own `cast_assoc` output, and
        # setting a field on each entry needs none of it.
        %{changeset | changes: Map.put(changeset.changes, field, number(entries))}
    end
  end

  defp number(entries) do
    {numbered, _next} =
      Enum.map_reduce(entries, 0, fn entry, next ->
        if leaving?(entry),
          do: {entry, next},
          else: {put_change(entry, :position, next), next + 1}
      end)

    numbered
  end

  defp leaving?(%Ecto.Changeset{action: action}), do: action in [:delete, :replace]
  defp leaving?(_entry), do: false
end
