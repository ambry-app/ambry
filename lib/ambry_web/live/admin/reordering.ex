defmodule AmbryWeb.Admin.Reordering do
  @moduledoc """
  Ordered `has_many` rows in an admin form: what the client does, and the one
  thing the server has to know about it.

  Deliberately not drag-and-drop. Ordering a book's two authors is a
  once-in-a-while act on a list of two or three, and a pair of buttons needs
  no JavaScript beyond a swap, works on a phone, and leaves the ordering in
  the params.

  **The move is a change event, like every other edit.** The `reorder-rows`
  hook swaps two rows' hidden `_sort` and `position` values and dispatches a
  change: the client edits the form, the server casts what it is posted, the
  same arrangement `inputs_for/1` documents for adding and removing rows.

  Handled as an event instead, the server would rewrite the form's params,
  which is a second mechanism indexing the same list as `_drop` — and `_drop`
  names a *slot*, so deleting one row and then moving another lands the delete
  on whichever row moved into that slot. Ecto reconciles the two itself
  (`cast_params/4` begins `sort -- drop`), and only when both arrive in one
  cast from the form, unedited.

  **Why a row carries a position at all.** `:sort_param` orders the incoming
  params, but order alone does not survive the round trip: `Ecto.Association.Has`
  has no `:ordered` field, so a reorder that changes no field leaves every
  child changeset empty, `Relation.cast` returns `:ignore`, and the buttons
  visibly work while saving nothing. So each row renders a hidden `position`
  holding its rendered index, and `Ambry.Ecto.Positions` renumbers them on the
  way to the database.
  """

  import Ecto.Changeset

  @doc """
  How many rows of an ordered list the form is actually rendering.

  Not `length(get_assoc(changeset, assoc))`: a row removed with the ✕ is still
  *in* the association, marked for replacement, and `inputs_for` skips it
  while a plain count does not. The form would believe there is one more row
  than the operator can see.

  Three call sites ask it: whether to offer the arrows, what the last index
  is, and whether the list is empty.
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
