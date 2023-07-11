defmodule AmbryScraping.Audible.Authors do
  @moduledoc """
  Audible web-scraping API for authors
  """

  alias AmbryScraping.Audible.Browser
  alias AmbryScraping.{HTMLToMD, Image}

  defmodule Author do
    @moduledoc false
    defstruct [:asin, :name, :description, :image]
  end

  def details(asin) do
    with {:ok, author_html} <- Browser.get_page_html("/author/#{asin}"),
         {:ok, author_document} <- Floki.parse_document(author_html) do
      {:ok, parse_author_details(asin, author_document)}
    end
  end

  defp parse_author_details(asin, author_document) do
    %Author{
      asin: asin,
      name: parse_name(author_document),
      description: parse_description(author_document),
      image: parse_image(author_document)
    }
  end

  defp parse_name(document) do
    document |> Floki.find("h1.bc-size-extra-large") |> Floki.text()
  end

  defp parse_description(document) do
    case Floki.find(document, "div.bc-expander-content span.bc-text") do
      [] ->
        nil

      [span] ->
        span
        |> Floki.children()
        |> HTMLToMD.html_to_md()
    end
  end

  @src_trailing ~r/\.__.*?__\./
  defp parse_image(document) do
    case document
         |> Floki.find("div.image-mask img.author-image-outline")
         |> Floki.attribute("src") do
      [src] ->
        src = String.replace(src, @src_trailing, ".")
        Image.fetch_from_source(src)

      _else ->
        nil
    end
  end
end
