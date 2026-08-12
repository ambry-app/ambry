defmodule Ambry.Media.Media.Chapter do
  @moduledoc """
  One chapter: a marker on the book's timeline, and a title for it.

  These are two different facts with two different levels of trust, and the
  whole point of this schema is that they are tracked separately.

  ## Markers are file-derived; titles are best-available

  A marker is a **position**, and a position is only meaningful against the
  actual bytes being played. Audible's chapter times describe Audible's
  retail edition, not somebody's rip — the offsets start seconds off and the
  error compounds across a book — so provider timestamps are **never**
  applied to the timeline. That is inherent to the data, not a bug anyone can
  fix, which is why the whole marker/title split exists. Where the markers
  came from is recorded once for the list, on the media
  (`chapter_marker_source`).

  A title is just a name, and a wrong one is a cosmetic problem rather than a
  broken seek. So titles come from wherever the best one is available, per
  row, and `title_source` records which:

    * `:embedded` — read out of the file's own chapter atoms or CHAP frames
    * `:filename` — the file's name, for chapter-per-file recordings
    * `:provider` — Audnexus/Audible and friends, poured onto file-derived
      markers by the merge
    * `:generated` — "Chapter 7", the floor
    * `:manual` — the operator typed it

  ## Why a title is always present

  `title` stays required even for a markers-only extraction, which gets a
  generated "Chapter N". Clients need something to show — a mobile chapter
  list of blanks is worse than a boring one — and the alternative, a nullable
  title every render surface has to special-case, buys nothing.

  `:generated` is what keeps that honest: it marks a title **nobody chose**,
  so the merge may overwrite it freely and the editor can render it as the
  placeholder it is. An operator's `:manual` title, by contrast, is an answer
  and survives.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  # `title_source` is part of the stored fact, not a view of it: a title
  # nobody chose has to still say so tomorrow, or the next merge can't tell
  # what it may overwrite.
  @derive {Jason.Encoder, only: [:time, :title, :title_source]}

  @title_sources [:embedded, :filename, :provider, :generated, :manual]

  embedded_schema do
    field :time, :decimal
    field :title, :string
    field :title_source, Ecto.Enum, values: @title_sources
  end

  def title_sources, do: @title_sources

  @doc """
  Whether this title is a placeholder rather than something anybody chose.

  The merge overwrites these without asking; a title with any other source is
  an answer and is only replaced deliberately.
  """
  def generated_title?(%__MODULE__{title_source: :generated}), do: true
  def generated_title?(%__MODULE__{}), do: false

  @doc """
  The floor: what a marker is called when nothing else has named it.
  """
  def generated_title(index), do: "Chapter #{index + 1}"

  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:time, :title, :title_source])
    |> validate_required([:time, :title])
    |> validate_inclusion(:title_source, @title_sources)
  end

  @doc """
  Renumbers the generated titles in a cast list of chapter changesets.

  The generated floor is a *position*, so it has to stop saying "Chapter 7"
  the moment a row is inserted above it. Titles anybody chose — typed, or
  accepted from a provider — are left exactly where they are, which is the
  whole reason `:generated` is tracked separately from every other source.

  This also gives a freshly-added blank row a title, so adding one doesn't
  greet the operator with a validation error on a field they were about to
  get to anyway.
  """
  def renumber_changesets(chapter_changesets) do
    chapter_changesets
    # A dropped row is still in the list, marked for deletion; numbering
    # around it would leave a gap the operator never asked for.
    |> Enum.reduce({[], 0}, fn chapter, {acc, index} ->
      if chapter.action == :replace do
        {[chapter | acc], index}
      else
        {[maybe_generate_title(chapter, index) | acc], index + 1}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp maybe_generate_title(chapter, index) do
    title = get_field(chapter, :title)
    source = get_field(chapter, :title_source)

    if blank?(title) or source == :generated do
      chapter
      |> put_change(:title, generated_title(index))
      |> put_change(:title_source, :generated)
    else
      chapter
    end
  end

  defp blank?(nil), do: true
  defp blank?(title) when is_binary(title), do: String.trim(title) == ""

  @doc """
  Whether a cast moved any marker — the trigger for recording the timeline
  as the operator's (`chapter_marker_source: :manual`), shared by every
  parent schema that embeds chapters.

  A chapter is an embed with no primary key, so Ecto can't match incoming
  params to existing rows: every cast replaces the whole list, and the
  change is the outgoing rows AND the incoming ones. Comparing against both
  makes any edit at all look like a moved marker — hence the reject on
  `action: :replace`.
  """
  def times_moved?(before_chapters, chapter_changesets) do
    before = before_chapters |> List.wrap() |> Enum.map(& &1.time)

    after_times =
      chapter_changesets
      |> Enum.reject(&(&1.action == :replace))
      |> Enum.map(&get_field(&1, :time))

    not times_equal?(before, after_times)
  end

  defp times_equal?(before, after_times) do
    length(before) == length(after_times) and
      before |> Enum.zip(after_times) |> Enum.all?(fn {a, b} -> decimal_equal?(a, b) end)
  end

  defp decimal_equal?(nil, nil), do: true
  defp decimal_equal?(nil, _b), do: false
  defp decimal_equal?(_a, nil), do: false
  defp decimal_equal?(a, b), do: Decimal.equal?(a, b)
end
