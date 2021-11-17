defmodule AmbryWeb.API.ChapterView do
  @moduledoc """
  Not a real view, just a helper function for rendering chapters.
  """

  alias AmbryWeb.Hashids

  def chapters(chapters, duration) do
    chapters
    |> Enum.chunk_every(2, 1)
    |> Enum.with_index()
    |> Enum.map(fn
      {[chapter, next], idx} ->
        %{
          id: Hashids.encode(idx),
          title: chapter.title,
          startTime: Decimal.to_float(chapter.time),
          endTime: Decimal.to_float(next.time)
        }

      {[last_chapter], idx} ->
        %{
          id: Hashids.encode(idx),
          title: last_chapter.title,
          startTime: Decimal.to_float(last_chapter.time),
          endTime: duration
        }
    end)
  end
end
