defmodule AmbryScraping.GoodReads.Authors do
  @moduledoc """
  GoodReads web-scraping API for authors
  """

  alias AmbryScraping.GoodReads.Books
  alias AmbryScraping.GoodReads.Browser
  alias AmbryScraping.HTMLToMD
  alias AmbryScraping.Image

  defmodule Author do
    @moduledoc false
    defstruct [:id, :name, :description, :image]
  end

  def details("author:" <> id = full_id) do
    with {:ok, author_html} <- Browser.get_page_html("/author/show/#{id}"),
         {:ok, photos_html} <- Browser.get_page_html("/photo/author/#{id}"),
         {:ok, author_document} <- Floki.parse_document(author_html),
         {:ok, photos_document} <- Floki.parse_document(photos_html) do
      {:ok, parse_author_details(full_id, author_document, photos_document)}
    end
  end

  defp parse_author_details(full_id, author_document, photos_document) do
    %Author{
      id: full_id,
      name: parse_name(author_document),
      description: parse_description(author_document),
      image: parse_image(photos_document)
    }
  end

  defp parse_name(document) do
    document |> Floki.find("h1.authorName") |> Floki.text()
  end

  defp parse_description(document) do
    case Floki.find(document, "div.aboutAuthorInfo span[id^='freeText']:last-of-type") do
      [] ->
        nil

      [span] ->
        span
        |> Floki.children()
        |> HTMLToMD.html_to_md()
    end
  end

  defp parse_image(document) do
    case document |> Floki.find("ul.photoList li.profile img") |> Floki.attribute("src") do
      [src] ->
        src = String.replace(src, "p2", "p8")
        Image.fetch_from_source(src)

      _else ->
        nil
    end
  end

  def search(name) do
    with {:ok, %{results: results}} <- Books.search(name) do
      downcased_name = String.downcase(name)

      results
      |> Enum.flat_map(& &1.contributors)
      |> Enum.uniq_by(& &1.id)
      |> Enum.flat_map(fn contributor ->
        case String.jaro_distance(downcased_name, String.downcase(contributor.name)) do
          x when x >= 0.8 -> [{contributor, x}]
          _else -> []
        end
      end)
      |> Enum.sort_by(fn {_contributor, score} -> score end, :desc)
      |> Enum.map(&elem(&1, 0))
    end
  end
end
