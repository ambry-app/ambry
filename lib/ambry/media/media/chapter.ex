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
end
