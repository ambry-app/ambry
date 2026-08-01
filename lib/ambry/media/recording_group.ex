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

    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recording_group, attrs) do
    cast(recording_group, attrs, [:name])
  end
end
