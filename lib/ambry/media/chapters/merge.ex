defmodule Ambry.Media.Chapters.Merge do
  @moduledoc """
  Pouring a list of titles onto a list of markers.

  Markers come from the files and are trusted; titles come from wherever the
  best ones are. The two lists describe the same book but not the same
  artifact, so they rarely line up one-for-one:

    * a retail edition carries "Opening Credits" and "End Credits" that a rip
      doesn't have, or the other way round;
    * a rip splits or merges a chapter the catalogue doesn't;
    * absolute timestamps have drifted by minutes by the end of the book,
      because the retail master and the rip aren't the same encode.

  ## Why durations and not times

  Matching by absolute position fails precisely where it matters: the further
  into the book, the worse the drift.

  Durations are local. However far the two timelines have wandered apart, a
  chapter that runs 18m22s in the retail edition runs about 18m22s in the rip,
  because it's the same narration. So the merge aligns the two *sequences of
  durations* and is immune to accumulated offset by construction. Aligning
  sequences rather than pairing them elementwise is also what absorbs the
  extra credits entry: an unmatched title is a gap, not a shift of everything
  after it.

  When the two lists are the same length, none of that is needed and the merge
  is index-wise, which is the common case. A title list with no timestamps is
  index-wise too.

  It never moves a marker. An incoming list's times are read only to compute
  its durations and are then thrown away: a provider that is minutes wrong
  about where chapter 30 starts is still right about what it's called.
  """

  alias Ambry.Media.Media.Chapter

  # The gap penalty sits at half the worst possible match: two gaps cost 1.0,
  # a hopeless match costs 1.0, and ties go to matching.
  @gap 0.5

  # The final entry of each list has no following duration to compare, so the
  # ends are matched on faith: cheap enough to prefer over a gap, dear enough
  # not to force a bad pairing.
  @unknown_cost 0.15

  @doc """
  Pours `incoming` titles onto `markers`, returning `{chapters, alignment}`.

  `markers` are the recording's existing chapters; `incoming` is a list of
  `%{title: String.t(), time: Decimal.t() | nil}` proposals. The result has
  exactly as many chapters as there were markers, at exactly the same times.

  `source` is recorded on every title this replaces, so the editor can say
  where each name came from and a later merge knows what is safe to
  overwrite.
  """
  def titles(markers, incoming, source \\ :provider) do
    alignment = align(markers, incoming)
    by_marker = Map.new(alignment, fn {i, j} -> {i, j} end)
    incoming = List.to_tuple(incoming)

    chapters =
      markers
      |> Enum.with_index()
      |> Enum.map(fn {marker, index} ->
        case Map.get(by_marker, index) do
          nil -> marker
          j -> retitle(marker, elem(incoming, j), source)
        end
      end)

    {chapters, alignment}
  end

  @doc """
  How the two lists pair up, as `{marker_index, incoming_index}` tuples.

  Either side may be `nil`: a marker with no title offered to it, or a title
  with no marker to land on. In timeline order, so it renders as a
  side-by-side preview.
  """
  def align(markers, incoming)

  def align([], incoming), do: Enum.map(0..(length(incoming) - 1)//1, &{nil, &1})
  def align(markers, []), do: Enum.map(0..(length(markers) - 1)//1, &{&1, nil})

  def align(markers, incoming) do
    cond do
      length(markers) == length(incoming) -> index_wise(length(markers), length(incoming))
      not timed?(incoming) -> index_wise(length(markers), length(incoming))
      true -> by_durations(markers, incoming)
    end
  end

  @doc """
  A one-line summary of an alignment, for the operator about to accept it.
  """
  def summarize(alignment) do
    matched = Enum.count(alignment, fn {i, j} -> i && j end)
    unmatched_markers = Enum.count(alignment, fn {i, j} -> i && is_nil(j) end)
    extra_titles = Enum.count(alignment, fn {i, j} -> is_nil(i) && j end)

    %{matched: matched, unmatched_markers: unmatched_markers, extra_titles: extra_titles}
  end

  defp retitle(marker, %{title: title}, source) do
    case present(title) do
      nil -> marker
      title -> %{marker | title: title, title_source: source}
    end
  end

  # Index-wise, with whatever is left over trailing off the end. Not an
  # alignment so much as an admission that there is nothing to align on.
  defp index_wise(n, m) do
    paired = for index <- 0..(min(n, m) - 1)//1, do: {index, index}
    marker_tail = for index <- min(n, m)..(n - 1)//1, do: {index, nil}
    title_tail = for index <- min(n, m)..(m - 1)//1, do: {nil, index}

    paired ++ marker_tail ++ title_tail
  end

  defp timed?(incoming), do: Enum.all?(incoming, &match?(%Decimal{}, &1[:time] || &1.time))

  defp by_durations(markers, incoming) do
    marker_durations = durations(Enum.map(markers, & &1.time))
    incoming_durations = durations(Enum.map(incoming, & &1.time))

    traceback(backpointers(marker_durations, incoming_durations))
  end

  # The gap to the next entry. The last one has no next and says so, since
  # the two lists can legitimately disagree about where the book ends.
  defp durations(times) do
    times
    |> Enum.map(&Decimal.to_float/1)
    |> Enum.chunk_every(2, 1)
    |> Enum.map(fn
      [from, to] -> to - from
      [_last] -> :unknown
    end)
    |> List.to_tuple()
  end

  # Needleman-Wunsch: every cell is the cheapest way to have consumed i
  # markers and j titles, and the direction it came from.
  defp backpointers(markers, incoming) do
    n = tuple_size(markers)
    m = tuple_size(incoming)

    first_row =
      Map.new(0..m, fn j -> {{0, j}, {j * @gap, if(j == 0, do: :done, else: :left)}} end)

    Enum.reduce(1..n//1, first_row, fn i, grid ->
      Enum.reduce(1..m//1, Map.put(grid, {i, 0}, {i * @gap, :up}), fn j, grid ->
        {diagonal, _} = grid[{i - 1, j - 1}]
        {up, _} = grid[{i - 1, j}]
        {left, _} = grid[{i, j - 1}]

        Map.put(
          grid,
          {i, j},
          Enum.min_by(
            [
              {diagonal + cost(elem(markers, i - 1), elem(incoming, j - 1)), :diagonal},
              {up + @gap, :up},
              {left + @gap, :left}
            ],
            &elem(&1, 0)
          )
        )
      end)
    end)
    |> then(&{&1, n, m})
  end

  defp cost(:unknown, _incoming), do: @unknown_cost
  defp cost(_marker, :unknown), do: @unknown_cost

  defp cost(marker, incoming) do
    largest = max(abs(marker), abs(incoming))

    if largest == 0, do: 0.0, else: min(abs(marker - incoming) / largest, 1.0)
  end

  defp traceback({grid, n, m}) do
    traceback(grid, n, m, [])
  end

  defp traceback(_grid, 0, 0, acc), do: acc

  defp traceback(grid, i, j, acc) do
    case grid[{i, j}] do
      {_cost, :diagonal} -> traceback(grid, i - 1, j - 1, [{i - 1, j - 1} | acc])
      {_cost, :up} -> traceback(grid, i - 1, j, [{i - 1, nil} | acc])
      {_cost, :left} -> traceback(grid, i, j - 1, [{nil, j - 1} | acc])
      {_cost, :done} -> acc
    end
  end

  defp present(nil), do: nil

  defp present(string) when is_binary(string) do
    case String.trim(string) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Re-numbers every generated title, after rows were added or removed.

  A generated title is a position, so "Chapter 7" stops being Chapter 7 the
  moment something is inserted above it. Chosen titles are left alone.
  """
  def renumber(chapters) do
    chapters
    |> Enum.with_index()
    |> Enum.map(fn {chapter, index} ->
      if Chapter.generated_title?(chapter),
        do: %{chapter | title: Chapter.generated_title(index)},
        else: chapter
    end)
  end
end
