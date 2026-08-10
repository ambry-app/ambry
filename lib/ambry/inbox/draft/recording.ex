defmodule Ambry.Inbox.Draft.Recording do
  @moduledoc """
  What the Media created by this import should say.

  In the walking skeleton a recording is always new. "This release is a better
  rip of an existing recording" — 3a's replace/upgrade workflow — is the third
  identity option this schema is shaped to grow, and is deliberately out of
  the first cut.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.SourceRef

  @primary_key false

  embedded_schema do
    field :confidence, :float
    field :query, :string
    field :query_fields, :map, default: %{}
    field :approved, :boolean, default: false

    # Whether a human has ticked/unticked records at this level — the seeder
    # also writes `sources` and `approved`, so neither can carry the
    # distinction `Draft.curated?/1` needs. Same name and reason as
    # `PersonDecision.evidence_curated`.
    field :evidence_curated, :boolean, default: false

    # Which records describe this recording. Hardcover, rreading-glasses and
    # Audible will all have a record of a popular reading — and the databases
    # keep out-of-print editions the storefront has scrubbed — so more than
    # one is normal and each may contribute a different field.
    embeds_many :sources, SourceRef, on_replace: :delete

    # Why nothing was filled in from a match. A doubted candidate stays in the
    # list to be chosen but is not allowed to describe the file, and the
    # operator was previously given no way to tell that apart from "no
    # provider had anything" — the two look identical once the fields are
    # empty.
    field :doubt, Ecto.Enum, values: [:none, :nothing_found, :narrator_conflict, :low_confidence]
    field :doubt_detail, :string

    embeds_one :title, Field, on_replace: :update
    embeds_one :published, Field, on_replace: :update

    # A recording's release date is as capable of being year-only as a work's,
    # and Media has carried the column all along — the draft simply never
    # decided it, so approval fell back to the schema default of `:full` and
    # a date known only to the year rendered as a real release day. That is
    # the exact bug the v1.9.0 punch list fixed for the import forms, still
    # live on this side of the form.
    embeds_one :published_format, Field, on_replace: :update
    embeds_one :publisher, Field, on_replace: :update
    embeds_one :description, Field, on_replace: :update
    embeds_one :cover, Field, on_replace: :update

    embeds_many :narrators, Credit, on_replace: :delete
  end

  @doc false
  def changeset(recording, attrs) do
    recording
    |> cast(attrs, [
      :confidence,
      :query,
      :query_fields,
      :approved,
      :evidence_curated,
      :doubt,
      :doubt_detail
    ])
    |> cast_embed(:sources)
    |> cast_embed(:title)
    |> cast_embed(:published)
    |> cast_embed(:published_format)
    |> cast_embed(:publisher)
    |> cast_embed(:description)
    |> cast_embed(:cover)
    |> cast_embed(:narrators)
    |> align_published_format()
  end

  # Same aligner as `Work.changeset/2`, for the same reason: every route into
  # the draft ends here, so this is the one place the format can be kept in
  # step with the date. The work side had it and this side didn't, so typing
  # a release date by hand settled one half of a two-column fact.
  defp align_published_format(changeset) do
    case {get_field(changeset, :published), get_field(changeset, :published_format)} do
      {%Field{} = published, %Field{} = format} ->
        case Field.follow_date(format, published) do
          ^format -> changeset
          aligned -> settle_format(changeset, aligned)
        end

      _nothing_to_align ->
        changeset
    end
  end

  defp settle_format(changeset, aligned) do
    put_change(
      changeset,
      :published_format,
      Map.take(aligned, [:value, :source, :chosen_key, :approved])
    )
  end

  @doc """
  Everything about this recording that still needs a human.
  """
  def unresolved(%__MODULE__{} = recording) do
    identity(recording) ++
      field(recording.title, "Recording title") ++
      field(recording.published, "Release date") ++
      field(recording.published_format, "Release date display format") ++
      field(recording.publisher, "Publisher") ++
      field(recording.description, "Description") ++
      field(recording.cover, "Cover image") ++
      credits(recording.narrators)
  end

  defp identity(%__MODULE__{approved: true}), do: []

  defp identity(%__MODULE__{}),
    do: [
      %{section: :recording, label: "Which records describe this recording", state: :unconfirmed}
    ]

  @doc """
  Whether the operator has said this provider record describes the recording.
  """
  def uses?(%__MODULE__{sources: sources}, record),
    do: Enum.any?(sources, &SourceRef.points_at?(&1, record))

  @doc """
  Whether the operator has settled this as a recording no catalogue lists.

  A real answer, and the one that settles the many recordings that genuinely
  aren't listed anywhere — a delisted edition disappears from Audible's search
  *and* from direct ASIN lookup, so "not found" is a fact about the catalogue,
  not a failure of the import.
  """
  def uncatalogued?(%__MODULE__{sources: [], approved: true}), do: true
  def uncatalogued?(%__MODULE__{}), do: false

  defp field(nil, _label), do: []

  defp field(field, label) do
    if Field.resolved?(field),
      do: [],
      else: [%{section: :recording, label: label, state: Field.state(field)}]
  end

  defp credits(narrators) do
    narrators
    |> Enum.reject(&Credit.resolved?/1)
    |> Enum.map(&%{section: :recording, label: "Narrator: #{&1.name}", state: Credit.state(&1)})
  end
end
