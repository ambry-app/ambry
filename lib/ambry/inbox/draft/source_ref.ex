defmodule Ambry.Inbox.Draft.SourceRef do
  @moduledoc """
  A pointer at one provider record the operator has said describes this import.

  The records themselves are *evidence* and live on `inbox_items.matches`,
  where discovery and re-searching write them. Which ones count is a
  *decision*, so it lives in the draft — that's the same boundary the whole
  draft/matches split is built on, and it's what lets a re-search add records
  without touching a curated choice.

  More than one is the normal case. Hardcover and rreading-glasses both having
  a record of Leviathan Wakes doesn't make it two books; it makes it one book
  two databases know about, and each knows things the other doesn't.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :source, :string
    field :id, :string
  end

  @doc false
  def changeset(source_ref, attrs) do
    source_ref
    |> cast(attrs, [:source, :id])
    |> validate_required([:source, :id])
  end

  @doc "The ref for a record, as stored."
  def of(record), do: %__MODULE__{source: record["source"], id: to_string(record["id"])}

  @doc "Whether this ref points at the given record."
  def points_at?(%__MODULE__{} = ref, record),
    do: ref.source == record["source"] and ref.id == to_string(record["id"])
end
