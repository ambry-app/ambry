defmodule Ambry.Inbox.Draft.Chapters do
  @moduledoc """
  The recording's chapter list, curated before import.

  Markers are file-derived facts and titles are per-row decisions. The rows
  are seeded from what the probe read out of the files, so the form states
  what they carry without re-reading them; the operator may retitle rows,
  pour provider titles on, or re-read the files, and import takes the curated
  list.

  **Seeded approved**, because the file's own answer is the lone proposer.
  Ticking a record later surfaces title chips but never un-approves:
  re-derivation must not un-answer. Editing rows or applying a merge sets
  `curated`, which survives reseeds.

  Rows reuse `Ambry.Media.Media.Chapter`, the exact embed the created Media
  will store, so nothing is translated at approval.

  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media.Chapter

  @primary_key false

  embedded_schema do
    field :chapter_marker_source, Ecto.Enum, values: [:embedded, :file_boundaries, :manual]
    field :approved, :boolean, default: true

    # Touched by the operator — a retyped title, a poured merge, a re-read.
    # Survives reseeds.
    field :curated, :boolean, default: false

    embeds_many :chapters, Chapter, on_replace: :delete
  end

  @doc false
  def changeset(chapters, attrs) do
    chapters
    |> cast(attrs, [:chapter_marker_source, :approved, :curated])
    |> cast_embed(:chapters,
      sort_param: :chapters_sort,
      drop_param: :chapters_drop,
      with: &chapter_row/2
    )
    |> renumber_generated()
    |> track_marker_source()
  end

  # The rule `Media.changeset/3` enforces: a moved marker makes the timeline
  # the operator's. The draft autosaves through here, so a time nudged in the
  # inbox must stop claiming the probe's source.
  defp track_marker_source(changeset) do
    cond do
      get_change(changeset, :chapter_marker_source) -> changeset
      not times_moved?(changeset) -> changeset
      true -> put_change(changeset, :chapter_marker_source, :manual)
    end
  end

  defp times_moved?(changeset) do
    case fetch_change(changeset, :chapters) do
      {:ok, chapters} -> Chapter.times_moved?(changeset.data.chapters, chapters)
      :error -> false
    end
  end

  # Validation gates saving; the invariant gates importing. The inbox
  # autosaves every keystroke, so a freshly-added row with no time yet has to
  # be *storable*, and `resolved?/1` is what keeps it out of the importer.
  defp chapter_row(chapter, attrs) do
    chapter
    |> cast(attrs, [:time, :title, :title_source])
    |> validate_inclusion(:title_source, Chapter.title_sources())
  end

  # The media form renumbers at its LiveView boundary; the inbox autosaves
  # through this changeset, so it renumbers here or a dropped row leaves
  # "Chapter 7" naming the sixth marker until import.
  defp renumber_generated(changeset) do
    case get_change(changeset, :chapters) do
      nil -> changeset
      chapters -> put_change(changeset, :chapters, Chapter.renumber_changesets(chapters))
    end
  end

  @doc """
  Whether this decision still needs a human. The list always holds an honest
  answer, so it is unresolved only where a half-made row has no time: the one
  thing the lax row changeset lets through that import must not receive.
  """
  def resolved?(%__MODULE__{approved: approved, chapters: rows}),
    do: approved and Enum.all?(rows, & &1.time)
end
