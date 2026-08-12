defmodule Ambry.Media.RecordingGroup do
  @moduledoc """
  A set of separately-released recordings that together cover one work.

  Examples: GraphicAudio's "Part 1 of 3" releases, or episodic full-cast
  seasons ("The Audio Immersion Experience — Season One"). A group is to
  media what a series is to books: a named, first-class entity its members
  point at with a `part_number`. The set-level facts live here — the name
  (required), how many releases the set has when known (`parts_total`), and
  what one release is called (`part_word`) — while per-release facts (cover,
  date, chapters) live on each media.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Media.Media

  schema "recording_groups" do
    # the work this set covers, same as its members' book — an episodic
    # season that drifts across book boundaries pins to its primary book
    belongs_to :book, Book
    has_many :media, Media, preload_order: [asc: :part_number]

    # a local name: it distinguishes this set from the book's OTHER
    # recordings ("Graphic Audio"), so it's unique per book, not globally —
    # displays compose "name (book)" where context is missing
    field :name, :string
    field :parts_total, :integer

    # whether the name renders on the set's stacked tile — an explicit
    # per-group operator choice, never inferred from the name itself
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
    recording_group
    |> cast(attrs, [:name, :book_id, :parts_total, :show_label, :part_word, :part_word_plural])
    |> validate_required([:name, :book_id])
    |> validate_number(:parts_total, greater_than_or_equal_to: 1)
    |> check_constraint(:parts_total, name: "recording_groups_parts_total_positive")
    |> unique_constraint([:book_id, :name],
      message: "this book already has a set by that name"
    )
  end

  @doc "The singular word for one release in this set, defaulting to \"part\"."
  def part_word(nil), do: "part"
  def part_word(%__MODULE__{} = group), do: group.part_word || "part"

  @doc "The plural word for this set's releases, defaulting to \"parts\"."
  def part_word_plural(nil), do: "parts"
  def part_word_plural(%__MODULE__{} = group), do: group.part_word_plural || "parts"
end
