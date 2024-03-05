defmodule AmbryScraping.Audnexus.Books do
  @moduledoc """
  Audnexus Books API.
  """

  @url "https://api.audnex.us/books"

  defmodule Chapters do
    @moduledoc false
    defstruct [:asin, :brand_intro_duration_ms, :brand_outro_duration_ms, :chapters]
  end

  defmodule Chapter do
    @moduledoc false
    defstruct [
      :length_ms,
      :start_offset_ms,
      :start_offset_sec,
      :title
    ]
  end

  def chapters(asin) do
    case Req.get("#{@url}/#{asin}/chapters", retry: false) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        parse_chapter_info(response.body)

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_chapter_info(chapter_info) do
    {:ok,
     %Chapters{
       asin: chapter_info["asin"],
       brand_intro_duration_ms: chapter_info["brandIntroDurationMs"],
       brand_outro_duration_ms: chapter_info["brandOutroDurationMs"],
       chapters: Enum.map(List.wrap(chapter_info["chapters"]), &parse_chapter/1)
     }}
  end

  defp parse_chapter(chapter) do
    %Chapter{
      length_ms: chapter["lengthMs"],
      start_offset_ms: chapter["startOffsetMs"],
      start_offset_sec: chapter["startOffsetSec"],
      title: chapter["title"]
    }
  end
end
