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

    # The provider record this proposal came out of, when it came out of one —
    # written into the field's provenance at approval, which is what lets a
    # later edit-form search recognize the record that filled the field.
    field :record, :string

    # Date proposals only: the display precision the proposing source knew
    # ("full" / "year_month" / "year"). A date and its precision are one
    # fact — a provider that knows only the year proposes "2015 (year only)",
    # never a fake January 1st — so the candidate carries both and choosing
    # one settles both.
    field :format, :string
  end

  @doc """
  The precision a date proposal really has: a date whose day isn't a 1st is
  a full date whatever the source claims — year-only knowledge arrives as a
  literal Jan 1st, so only 1st-day dates are ambiguous enough for a claimed
  precision to mean anything.
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
  The key for a proposal coming from one provider record.

  The record's id is what makes it distinct — the provider alone isn't enough
  when a provider returned more than one record.
  """
  def key_for(%{"source" => source, "id" => id}) when not is_nil(id), do: "#{source}##{id}"

  # These come out of jsonb a provider filled in, so an id is not something to
  # rely on being there — and a missing one is a proposal that can't be told
  # apart from its provider's others, not a reason to fail building the draft.
  def key_for(%{"source" => source}), do: source
end
