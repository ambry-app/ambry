defmodule Ambry.Inbox.DuplicateDismissal do
  @moduledoc """
  A set of records the operator has said are not each other's duplicates.

  Keyed by the exact members rather than by the folded key they collided on.
  A dismissal should silence a finding that was looked at, never one that
  was not: a set that gains a third member is a different set, so it is a
  finding again and has to be answered again.

  Nothing cleans these up, because nothing has to. A dismissal whose members
  no longer all exist can never match a group again, so it is inert rather
  than wrong, and the alternative is a second delete trigger beside
  `track_delete` earning its keep on a table with two rows in it.
  """

  use Ecto.Schema

  schema "duplicate_dismissals" do
    field :kind, Ecto.Enum, values: ~w(person author narrator book series)a
    field :record_ids, {:array, :integer}
    field :dismissed_at, :utc_datetime
  end
end
