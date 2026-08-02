defmodule Ambry.Media.RecordingGroup do
  @moduledoc """
  A set of separately-released recordings that together cover one work.

  Examples: GraphicAudio's "Part 1 of 3" releases, or episodic full-cast
  seasons ("The Audio Immersion Experience — Season One"). The group itself is
  deliberately minimal — per-release facts (cover, date, chapters) live on
  each Media; the group exists so parts can be displayed together and, for
  episodic sets, carry a display name.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media

  schema "recording_groups" do
    has_many :media, Media, preload_order: [asc: :part_number]

    # organizational label; rendered on the set's stacked tile only when
    # the operator opts in via show_label (an explicit choice — label
    # presence alone never triggers user-facing rendering)
    field :name, :string
    field :show_label, :boolean, default: false

    # what one release in this set is called ("part" by default; "episode",
    # "volume", ...). Stored lowercase; display capitalizes as needed. nil
    # means the default wording.
    field :part_word, :string
    field :part_word_plural, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recording_group, attrs) do
    cast(recording_group, attrs, [:name, :show_label, :part_word, :part_word_plural])
  end

  @doc "The singular word for one release in this set, defaulting to \"part\"."
  def part_word(nil), do: "part"
  def part_word(%__MODULE__{} = group), do: group.part_word || "part"

  @doc "The plural word for this set's releases, defaulting to \"parts\"."
  def part_word_plural(nil), do: "parts"
  def part_word_plural(%__MODULE__{} = group), do: group.part_word_plural || "parts"
end
