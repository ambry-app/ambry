defmodule AmbryScraping.Audible.Authors do
  @moduledoc """
  Audible web-scraping API for authors
  """

  alias AmbryScraping.Audible.Browser
  alias AmbryScraping.HTMLToMD
  alias AmbryScraping.Image

  defmodule Author do
    @moduledoc false
    defstruct [:id, :name, :description, :image]
  end

  defmodule SearchResult do
    @moduledoc false
    defstruct [:id, :name]
  end

  def details(id) do
    with {:ok, author_html} <- Browser.get_page_html("/author/#{id}"),
         {:ok, author_document} <- Floki.parse_document(author_html) do
      {:ok, parse_author_details(id, author_document)}
    end
  end

  defp parse_author_details(id, author_document) do
    %Author{
      id: id,
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

  def search(name) do
    query = URI.encode_query(%{keywords: name})
    path = "/search" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    downcased_query_words =
      query |> String.downcase() |> String.split(" ", trim: true) |> Enum.reject(&(String.length(&1) < 2))

    with {:ok, search_results_html} <- Browser.get_page_html(path),
         {:ok, search_results_document} <- Floki.parse_document(search_results_html) do
      {:ok,
       search_results_document
       |> Floki.find("li.authorLabel a")
       |> Enum.map(fn link ->
         name = Floki.text(link)

         [url] = Floki.attribute(link, "href")
         uri = URI.parse(url)
         id = Path.basename(uri.path)

         %SearchResult{
           id: id,
           name: name
         }
       end)
       |> Enum.uniq_by(& &1.id)
       |> Enum.filter(fn author ->
         downcased_name = String.downcase(author.name)
         Enum.any?(downcased_query_words, &String.contains?(downcased_name, &1))
       end)}
    end
  end
end
