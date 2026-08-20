defmodule AmbryWeb.Admin.Reordering do
  @moduledoc """
  Ordered `has_many` rows in an admin form: what the client does, and the one
  thing the server has to know about it.

  Deliberately not drag-and-drop. Ordering a book's two authors is a
  once-in-a-while act on a list that is almost always two or three long, and a
  pair of buttons needs no JavaScript beyond a swap, works on a phone, and
  leaves the ordering itself in the params where it can be read.

  ## The move is a change event, like every other edit

  `inputs_for/1` documents adding and removing rows as buttons that carry a
  name and a value and dispatch a change: **the client edits the form, the
  server casts what it is posted.** Reordering is not in those docs, but it
  belongs to the same arrangement, and the `reorder-rows` hook implements it —
  it swaps two rows' hidden `_sort` values (which is the order) and their
  `position` values, then dispatches the change. Nothing here handles a move.

  It was an event once, and the handler rewrote the form's params: reorder the
  entries, renumber them, write the sort list back. That is a second mechanism
  indexing the same list as `_drop`, which names a *slot* — so deleting the
  second author and then moving the first one down landed the delete on the
  row that had just moved into that slot. The author who was deleted came
  back and the author who was kept was destroyed, silently, on save. Ecto
  reconciles the two itself (`cast_params/4` begins `sort -- drop`), and it
  can only do that when both arrive in one cast, from the form, unedited.

  ## Why a row carries a position at all

  `cast_assoc`'s `:sort_param` really does order the incoming params, but
  order alone does not survive the round trip: `Ecto.Association.Has` has no
  `:ordered` field (`Ecto.Embedded` does), so a reorder that changes no field
  leaves every child changeset empty, `Relation.cast` returns `:ignore`, and
  the association ends up with no change at all — buttons that visibly work
  and save nothing.

  So the order is carried by a real field. Each row renders a hidden
  `position` holding its rendered index, and swapping two of them is what
  makes the children genuinely differ; `Ambry.Ecto.Positions` renumbers them
  0..n on the way to the database.
  """

  import Ecto.Changeset

  @doc """
  How many rows of an ordered list the form is actually rendering.

  Not `length(get_assoc(changeset, assoc))`, which is the trap this exists to
  close: a row removed with the ✕ is still *in* the association, marked for
  replacement, and `inputs_for` skips it while a plain count does not. So the
  form believed there was one more row than the operator could see — the last
  visible row kept its "move down" arrow, pointing at a row that wasn't there,
  and a single remaining row still wore arrows at all.

  Every call site asks the same question ("how many rows are on screen") for
  three purposes: whether to offer the arrows, what the last index is, and
  whether to say the list is empty.
  """
  def row_count(%Ecto.Changeset{} = changeset, association) do
    changeset
    |> get_assoc(association)
    |> Enum.count(&rendered?/1)
  end

  # A child marked for replacement or deletion is gone from the form; the
  # struct form of a row (an unchanged association) is always rendered.
  defp rendered?(%Ecto.Changeset{action: action}), do: action not in [:replace, :delete]
  defp rendered?(_struct), do: true
end
