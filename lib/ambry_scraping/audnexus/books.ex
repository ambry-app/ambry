defmodule AmbryScraping.Audnexus.Books do
  @moduledoc false

  alias AmbryScraping.Audnexus.Chapter
  alias AmbryScraping.Audnexus.Chapters
  alias AmbryScraping.Audnexus.Client

  def chapters(asin) do
    case Client.get("/books/#{asin}/chapters", retry: false) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        parse_chapter_info(response.body)

      {:ok, %{status: status}} when status in 400..499 ->
        {:error, :not_found}

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
