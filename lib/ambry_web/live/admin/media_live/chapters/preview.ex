defmodule AmbryWeb.Admin.MediaLive.Chapters.Preview do
  @moduledoc """
  What an import is about to do to the chapter list, before it does it.

  Both chapter imports are destructive in their own way — one replaces the
  markers, the other overwrites the titles — and neither used to show
  anything but a wall of incoming chapter names. Which is exactly the wrong
  half: the operator can read chapter titles anywhere, and what they can't
  see is *how the two lists line up*, which is the only thing that can go
  wrong.
  """
  use AmbryWeb, :html

  import AmbryWeb.Admin.Components

  alias Ambry.Media.Media.Chapter

  attr :markers, :list, required: true, doc: "the recording's current chapters"
  attr :incoming, :list, required: true, doc: "the proposed titles, in their own order"
  attr :alignment, :list, required: true, doc: "from Ambry.Media.Chapters.Merge.align/2"
  attr :summary, :map, required: true, doc: "from Ambry.Media.Chapters.Merge.summarize/1"

  @doc """
  The side-by-side: markers on the left, the titles landing on them at right.
  """
  def alignment_preview(assigns) do
    assigns =
      assigns
      |> assign(:markers, List.to_tuple(assigns.markers))
      |> assign(:incoming, List.to_tuple(assigns.incoming))

    ~H"""
    <div class="space-y-2">
      <p class="pl-3 text-sm text-zinc-400">
        {counts(@summary)}
      </p>

      <div class="max-h-96 space-y-1 overflow-y-auto rounded-lg bg-zinc-900 p-4">
        <div class="grid-cols-[5.5rem_minmax(0,1fr)_1.5rem_minmax(0,1fr)] grid items-baseline gap-2">
          <.microlabel>Marker</.microlabel>
          <.microlabel>Now</.microlabel>
          <span></span>
          <.microlabel>After</.microlabel>
        </div>

        <div
          :for={{marker_index, incoming_index} <- @alignment}
          class="grid-cols-[5.5rem_minmax(0,1fr)_1.5rem_minmax(0,1fr)] grid items-baseline gap-2 text-sm"
        >
          <span class="font-mono text-xs tabular-nums text-zinc-400">
            {marker_time(@markers, marker_index)}
          </span>

          <span class={["truncate", marker_index && "text-zinc-300", is_nil(marker_index) && "text-zinc-500"]}>
            {marker_title(@markers, marker_index) || "no marker here"}
          </span>

          <span class="text-center text-xs text-zinc-500">{arrow(marker_index, incoming_index)}</span>

          <span class={[
            "truncate",
            incoming_index && marker_index && "text-zinc-100",
            is_nil(incoming_index) && "text-zinc-500",
            is_nil(marker_index) && "text-zinc-500 line-through"
          ]}>
            {incoming_title(@incoming, incoming_index) || "keeps its title"}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :chapters, :list, required: true
  attr :source, :atom, default: nil

  @doc """
  A plain list of proposed chapters, for a marker replacement — where there
  is no alignment to show, because the incoming list *is* the new timeline.
  """
  def chapter_preview(assigns) do
    ~H"""
    <div class="space-y-2">
      <p class="pl-3 text-sm text-zinc-400">
        {length(@chapters)} chapters, {marker_source_phrase(@source)}.
      </p>

      <div class="max-h-96 space-y-1 overflow-y-auto rounded-lg bg-zinc-900 p-4">
        <div
          :for={chapter <- @chapters}
          class="grid-cols-[5.5rem_minmax(0,1fr)] grid items-baseline gap-2 text-sm"
        >
          <span class="font-mono text-xs tabular-nums text-zinc-400">{timecode(chapter.time)}</span>
          <span class={[
            "truncate",
            chapter.title_source == :generated && "text-zinc-500",
            chapter.title_source != :generated && "text-zinc-300"
          ]}>
            {chapter.title}
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  How a title got its name, in one muted word for a dense row.

  `:generated` deliberately reads "auto" rather than naming a source: it is
  the absence of one.
  """
  def title_source_label(:generated), do: "auto"
  def title_source_label(:embedded), do: "file"
  def title_source_label(:filename), do: "name"
  def title_source_label(:provider), do: "audible"
  def title_source_label(:manual), do: "typed"
  def title_source_label(_unrecorded), do: nil

  @doc """
  Where a recording's markers came from, as a sentence the operator can act
  on.
  """
  def marker_source_phrase(:embedded), do: "read from the files' own chapter marks"

  def marker_source_phrase(:file_boundaries),
    do: "one per file, taken from where each file starts"

  def marker_source_phrase(:manual), do: "set by hand"
  def marker_source_phrase(_unrecorded), do: "from before this was recorded"

  @doc """
  What the titles of a chapter list are made of, counted by source.
  """
  def title_summary([]), do: nil

  def title_summary(chapters) do
    chapters
    |> Enum.frequencies_by(& &1.title_source)
    |> Enum.sort_by(fn {_source, count} -> -count end)
    |> Enum.map_join(", ", fn {source, count} ->
      "#{count} #{title_source_phrase(source)}"
    end)
  end

  defp title_source_phrase(:generated), do: "generated"
  defp title_source_phrase(:embedded), do: "from the files"
  defp title_source_phrase(:filename), do: "from the filenames"
  defp title_source_phrase(:provider), do: "from a provider"
  defp title_source_phrase(:manual), do: "typed"
  defp title_source_phrase(_unrecorded), do: "unrecorded"

  defp counts(%{matched: matched, unmatched_markers: unmatched, extra_titles: extra}) do
    [
      "#{matched} #{if matched == 1, do: "title lands", else: "titles land"} on a marker",
      unmatched > 0 &&
        "#{unmatched} #{if unmatched == 1, do: "marker keeps", else: "markers keep"} its title",
      extra > 0 &&
        "#{extra} extra #{if extra == 1, do: "title has", else: "titles have"} nowhere to go"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp arrow(nil, _incoming), do: "✕"
  defp arrow(_marker, nil), do: "·"
  defp arrow(_marker, _incoming), do: "→"

  defp marker_time(_markers, nil), do: "—"
  defp marker_time(markers, index), do: markers |> elem(index) |> Map.fetch!(:time) |> timecode()

  defp marker_title(_markers, nil), do: nil
  defp marker_title(markers, index), do: markers |> elem(index) |> Map.fetch!(:title)

  defp incoming_title(_incoming, nil), do: nil
  defp incoming_title(incoming, index), do: incoming |> elem(index) |> Map.fetch!(:title)

  @doc """
  Seconds as `h:mm:ss`, which is how a chapter position is read.
  """
  def timecode(nil), do: "—"

  def timecode(%Decimal{} = seconds) do
    total = seconds |> Decimal.round(0) |> Decimal.to_integer()

    hours = div(total, 3600)
    minutes = total |> div(60) |> rem(60)
    seconds = rem(total, 60)

    "#{hours}:#{pad(minutes)}:#{pad(seconds)}"
  end

  defp pad(number), do: number |> to_string() |> String.pad_leading(2, "0")

  @doc """
  The generated floor's wording, so the editor and the extractor agree.
  """
  defdelegate generated_title(index), to: Chapter
end
