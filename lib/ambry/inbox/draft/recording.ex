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

  @primary_key false

  embedded_schema do
    field :candidates, {:array, :map}, default: []
    field :confidence, :float
    field :query, :string
    field :query_fields, :map, default: %{}
    field :approved, :boolean, default: false

    # Which catalogue entry describes this recording — the sharpest fact
    # available about an import, because a file is a recording of exactly one
    # thing. `nil` with candidates present means the operator has said none of
    # them is it; the fields below then come from the file alone.
    field :selected_source, :string
    field :selected_id, :string

    # Why nothing was filled in from a match. A doubted candidate stays in the
    # list to be chosen but is not allowed to describe the file, and the
    # operator was previously given no way to tell that apart from "no
    # provider had anything" — the two look identical once the fields are
    # empty.
    field :doubt, Ecto.Enum, values: [:none, :nothing_found, :narrator_conflict, :low_confidence]
    field :doubt_detail, :string

    embeds_one :title, Field, on_replace: :update
    embeds_one :published, Field, on_replace: :update
    embeds_one :publisher, Field, on_replace: :update
    embeds_one :description, Field, on_replace: :update
    embeds_one :cover, Field, on_replace: :update

    embeds_many :narrators, Credit, on_replace: :delete
  end

  @doc false
  def changeset(recording, attrs) do
    recording
    |> cast(attrs, [
      :candidates,
      :confidence,
      :query,
      :query_fields,
      :approved,
      :selected_source,
      :selected_id,
      :doubt,
      :doubt_detail
    ])
    |> cast_embed(:title)
    |> cast_embed(:published)
    |> cast_embed(:publisher)
    |> cast_embed(:description)
    |> cast_embed(:cover)
    |> cast_embed(:narrators)
  end

  @doc """
  Everything about this recording that still needs a human.
  """
  def unresolved(%__MODULE__{} = recording) do
    identity(recording) ++
      field(recording.title, "Recording title") ++
      field(recording.published, "Release date") ++
      field(recording.publisher, "Publisher") ++
      field(recording.description, "Description") ++
      field(recording.cover, "Cover image") ++
      credits(recording.narrators)
  end

  defp identity(%__MODULE__{approved: true}), do: []

  defp identity(%__MODULE__{}),
    do: [%{section: :recording, label: "Which recording this is", state: :unconfirmed}]

  @doc """
  Whether a candidate is the one this recording was identified as.
  """
  def selected?(%__MODULE__{selected_source: nil}, _candidate), do: false

  def selected?(%__MODULE__{} = recording, candidate) do
    recording.selected_source == candidate["source"] and
      recording.selected_id == to_string(candidate["id"])
  end

  @doc """
  Whether the operator has said this release is in no catalogue.

  A real answer, and the one that settles the identity for the many recordings
  that genuinely aren't listed anywhere — a delisted edition disappears from
  Audible's search *and* from direct ASIN lookup, so "not found" is a fact
  about the catalogue, not a failure of the import.
  """
  def uncatalogued?(%__MODULE__{selected_source: nil, approved: true, candidates: [_ | _]}),
    do: true

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
