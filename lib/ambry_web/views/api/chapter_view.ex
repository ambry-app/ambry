defmodule AmbryWeb.API.ChapterView do
  @moduledoc """
  Not a real view, just a helper function for rendering chapters.
  """

  alias AmbryWeb.Hashids

  def chapters(chapters) do
    chapters
    |> Enum.chunk_every(2, 1)
    |> Enum.with_index()
    |> Enum.map(fn
      {[chapter, next], idx} ->
        %{
          id: Hashids.encode(idx),
          title: chapter.title,
          startTime: chapter.time |> Decimal.round() |> Decimal.to_integer(),
          endTime: next.time |> Decimal.round() |> Decimal.to_integer()
        }

      {[last_chapter], idx} ->
        %{
          id: Hashids.encode(idx),
          title: last_chapter.title,
          startTime: last_chapter.time |> Decimal.round() |> Decimal.to_integer(),
          endTime: nil
        }
    end)
  end
end
