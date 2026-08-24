defmodule Ambry.Inbox.Draft.Candidate do
  @moduledoc """
  One source's proposal for a scalar field.

  `source` doubles as the provenance source string written at approval
  (`"provider:hardcover"`, `"tags"`, `"manual"`), so a decision already knows
  where its value came from and no separate hint-collection layer is needed.

  `label` is what the operator reads, since `provider:rreading_glasses` is an
  id rather than a sentence.

  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :value, :string
    field :source, :string
    field :label, :string

    # What identifies this proposal, which is NOT `source`: two records from
    # one provider can both propose a release date, and keying on the provider
    # alone selects both chips and applies only the first.
    field :key, :string

    # The provider record this came out of, written into the field's
    # provenance at approval, which is what lets a later search recognize the
    # record that filled the field.
    field :record, :string

    # Date proposals only. A date and its precision are one fact: a provider
    # that knows only the year proposes "2015 (year only)" rather than a fake
    # January 1st, so choosing one settles both.
    field :format, :string
  end

  @doc """
  The precision a date proposal really has: year-only knowledge arrives as a
  literal January 1st, so only a 1st-day date is ambiguous enough for a
  claimed precision to mean anything.
  """
  def date_format(value, claimed) do
    case Date.from_iso8601(to_string(value || "")) do
      {:ok, %Date{day: day}} when day != 1 -> "full"
      _ambiguous_or_unparseable -> claimed
    end
  end

  @doc false
  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:value, :source, :label, :key, :record, :format])
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
  The key for a proposal from one provider record. The record's id is what
  makes it distinct, since a provider can return more than one.
  """
  def key_for(%{"source" => source, "id" => id}) when not is_nil(id), do: "#{source}##{id}"

  # Out of jsonb a provider filled in, so an id may be absent. A missing one
  # is a proposal that cannot be told from its provider's others, not a reason
  # to fail building the draft.
  def key_for(%{"source" => source}), do: source
end
