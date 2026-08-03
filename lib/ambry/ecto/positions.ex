defmodule Ambry.Ecto.Positions do
  @moduledoc """
  Keeps an ordered `has_many` numbered by its position in the list.

  Phoenix's `sort_param` already gives a form control over the *order* of an
  association's entries — it reorders the changesets before they're cast. What
  it can't do is make that order survive the round trip, because nothing
  writes it down. This does: after casting, each entry's `position` is set to
  where it actually sits.

  Entries on their way out are left exactly as they are and don't consume a
  number, so removing the first of three authors leaves 0, 1 — not a hole at
  0. They are deliberately kept in the list rather than filtered out: the
  list *is* the instruction to Ecto, and dropping an entry from it would make
  `on_replace: :delete` fire on something the operator never removed.
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
        # Written straight into `changes` rather than via `put_change/3`:
        # these entries have already been through `cast_assoc`, and Ecto
        # refuses to run its relation-change tracking over its own output
        # ("cannot replace related ... only once per assoc"). Nothing here
        # adds or removes an entry — it only sets a field on each — so the
        # tracking has nothing left to do anyway.
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
