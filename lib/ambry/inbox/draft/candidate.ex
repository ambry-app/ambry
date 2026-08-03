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
  end

  @doc false
  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:value, :source, :label])
    |> validate_required([:source])
  end
end
