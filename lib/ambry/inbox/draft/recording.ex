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
    field :approved, :boolean, default: false

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
    |> cast(attrs, [:candidates, :confidence, :query, :approved])
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
    do: [%{section: :recording, label: "Which recording", state: :unconfirmed}]

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
