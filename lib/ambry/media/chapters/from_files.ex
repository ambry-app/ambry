defmodule Ambry.Media.Chapters.FromFiles do
  @moduledoc """
  Chapter markers read out of the files themselves, at scan time.

  Markers are only ever taken from the actual bytes being played — that is
  1h's founding principle, and it is why no provider appears anywhere in this
  module. There are two ways a file states where its chapters are, and one
  way a folder does:

    * **embedded markers** — MP4 chapter atoms or ID3v2 CHAP frames, which
      ffprobe surfaces either way. Authoritative when present.
    * **file boundaries** — a chapter-per-file release, where the marker
      *is* where each file starts on the book timeline. Exact by
      construction: there is nothing to drift.

  A multi-file recording whose files each carry their own atoms (an m4b split
  into three parts, say) gets those, shifted onto the book timeline by each
  track's `start_offset`. Only when that isn't available do the boundaries
  themselves become the markers.

  ## Titles, and why most of them end up generated

  A chapter-per-file release names its files, and those names are the obvious
  title source, except that most of them are shelf labels rather than chapter
  names:

      001 -  01-28 This Is How You Lose the Time War.mp3
      002 -  02-28 This Is How You Lose the Time War.mp3

  Taking those literally gives twenty-eight chapters with twenty-eight nearly
  identical names, which is worse than "Chapter 1" because it looks like
  data. So a name list is only used if it still says something once its
  numbering is stripped: if every entry collapses to the same string, it was
  the book's title with a counter attached, and the generated floor wins.

  The floor is never a dead end — it records `:generated`, which is exactly
  what tells the titles merge it may overwrite freely. A release like this is
  the *ideal* input to an Audnexus title merge: exact markers, no real
  titles, nothing to lose.
  """

  alias Ambry.Media.Media.Chapter

  # Leading and trailing counters: "001 - ", "01-28 ", " - 03", "_5". Applied
  # repeatedly, because release names stack them ("001 -  01-28 Title").
  @leading ~r/^[\s._\-\[\(]*\d+([\s._\-]*(of|\/)[\s._\-]*\d+)?[\s._\-\]\)]*/i
  @trailing ~r/[\s._\-\[\(]*\d+([\s._\-]*(of|\/)[\s._\-]*\d+)?[\s._\-\]\)]*$/i
  @counter_words ~r/^(chapter|track|part|disc|cd|file|section)\b/i

  @doc """
  The chapters a set of probes offers, with where the markers came from.

  Returns `{chapters, marker_source}` — `{[], nil}` when the files say
  nothing about their own chapters, which is the ordinary case for a plain
  single-file mp3.

  `tracks` are the track attributes the scanner derived from the same probes,
  in the same order; their `start_offset`s are what put a per-file marker on
  the book's timeline.
  """
  def extract(probes, tracks)

  def extract([], _tracks), do: {[], nil}

  def extract([%{chapters: [_ | _] = chapters}], _tracks) do
    {embedded(chapters), :embedded}
  end

  def extract([_single_file_without_chapters], _tracks), do: {[], nil}

  def extract(probes, tracks) do
    if Enum.all?(probes, &(&1.chapters != [])) do
      {embedded_across(probes, tracks), :embedded}
    else
      {boundaries(probes, tracks), :file_boundaries}
    end
  end

  # A file's own markers are relative to that file; the book timeline is
  # absolute, so each one moves by where its track starts.
  defp embedded_across(probes, tracks) do
    probes
    |> Enum.zip(tracks)
    |> Enum.flat_map(fn {probe, track} ->
      Enum.map(probe.chapters, fn chapter ->
        %{chapter | time: Decimal.add(chapter.time, track.start_offset)}
      end)
    end)
    |> embedded()
  end

  defp embedded(chapters) do
    chapters
    |> Enum.with_index()
    |> Enum.map(fn {chapter, index} ->
      %{
        time: chapter.time,
        title: present(chapter.title) || Chapter.generated_title(index),
        title_source: if(present(chapter.title), do: :embedded, else: :generated)
      }
    end)
  end

  defp boundaries(probes, tracks) do
    {titles, source} = titles(probes)

    tracks
    |> Enum.with_index()
    |> Enum.map(fn {track, index} ->
      %{
        time: track.start_offset,
        title: Enum.at(titles, index) || Chapter.generated_title(index),
        title_source: source
      }
    end)
  end

  # Tags first, filenames second, the generated floor last — and each list is
  # taken whole or not at all, because a half-named chapter list reads as
  # data where it's really a gap.
  defp titles(probes) do
    tag_titles = Enum.map(probes, &clean(present(&1.tags && &1.tags.title)))

    file_titles =
      Enum.map(probes, &(&1.path |> Path.basename() |> Path.rootname() |> present() |> clean()))

    cond do
      usable?(tag_titles) -> {tag_titles, :embedded}
      usable?(file_titles) -> {file_titles, :filename}
      true -> {[], :generated}
    end
  end

  # "01 - Prologue" is a chapter called Prologue that happens to be first;
  # the counter is how the release kept its files in order, not part of the
  # name. Stripped only while something is left over, so a file honestly
  # called "1984" keeps its title.
  defp clean(nil), do: nil

  defp clean(title) do
    title
    |> String.replace(@leading, "")
    |> String.trim()
    |> case do
      "" -> title
      ^title -> title
      shorter -> clean(shorter)
    end
  end

  # Usable means: every file named, and the names still distinguish the
  # chapters once their numbering is gone. "Chapter 1..28" collapses to one
  # value and is rejected — which costs nothing, since rejecting it produces
  # the identical list from the floor, with an honest source on it.
  defp usable?(titles) do
    Enum.all?(titles, &is_binary/1) and
      titles |> Enum.map(&strip_numbering/1) |> Enum.uniq() |> length() > 1
  end

  defp strip_numbering(title) do
    title
    |> String.replace(@counter_words, "")
    |> strip_repeatedly(@leading)
    |> strip_repeatedly(@trailing)
    |> String.trim()
    |> String.downcase()
  end

  defp strip_repeatedly(string, pattern) do
    case String.replace(string, pattern, "") do
      ^string -> string
      shorter -> strip_repeatedly(shorter, pattern)
    end
  end

  defp present(nil), do: nil

  defp present(string) when is_binary(string) do
    case String.trim(string) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
