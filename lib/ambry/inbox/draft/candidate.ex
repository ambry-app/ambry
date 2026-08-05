defmodule Ambry.Inbox.Draft.Candidate do
  @moduledoc """
  One source's proposal for a scalar field.

  `source` doubles as the provenance source string written at approval
  (`"provider:hardcover"`, `"tags"`, `"manual"`), which is what lets the
  import form close 1d's loop without a separate hint-collection layer: the
  decision already knows where its value came from.

  `label` is what the operator reads — a provider's display name, or "the
  file's tags" — because `provider:rreading_glasses` is an id, not a sentence.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :value, :string
    field :source, :string
    field :label, :string

    # What identifies this proposal among the others. NOT the same as `source`:
    # two records from one provider both propose a release date, and keying the
    # choice on the provider alone selected both chips and could only ever
    # apply the first — the other value was unreachable.
    field :key, :string
  end

  @doc false
  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:value, :source, :label, :key])
    |> validate_required([:source])
    |> ensure_key()
  end

  defp ensure_key(changeset) do
    case get_field(changeset, :key) do
      nil -> put_change(changeset, :key, get_field(changeset, :source))
      _present -> changeset
    end
  end

  @doc """
  The key for a proposal coming from one provider record.

  The record's id is what makes it distinct — the provider alone isn't enough
  when a provider returned more than one record.
  """
  def key_for(%{"source" => source, "id" => id}), do: "#{source}##{id}"
end
