defmodule AmbryScraping.GoodReads.Books.Search do
  @moduledoc """
  GoodReads book search results
  """

  alias AmbryScraping.GoodReads.Browser
  alias AmbryScraping.Image

  defmodule Book do
    @moduledoc false
    defstruct [:id, :title, :contributors, :thumbnail]
  end

  defmodule Contributor do
    @moduledoc false
    defstruct [:id, :name, :type]
  end

  defmodule Thumbnail do
    @moduledoc false
    defstruct [:src, :data_url]
  end

  def search(query_string) do
    query = URI.encode_query(%{utf8: "✓", query: query_string})
    path = "/search" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    with {:ok, page_html} <- Browser.get_page_html(path),
         {:ok, document} <- Floki.parse_document(page_html) do
      {:ok, parse_books(document)}
    end
  end

  defp parse_books(document) do
    document
    |> Floki.find("tr[itemtype='http://schema.org/Book']")
    |> Enum.map(&parse_book/1)
  end

  defp parse_book(book_html) do
    %Book{
      id: "work:" <> parse_work_id(book_html),
      title: parse_book_title(book_html),
      contributors: parse_contributors(book_html),
      thumbnail: parse_thumbnail(book_html)
    }
  end

  defp parse_book_title(book_html) do
    book_html |> Floki.find("a.bookTitle span[itemprop='name']") |> Floki.text() |> clean_string()
  end

  defp parse_contributors(book_html) do
    book_html
    |> Floki.find("div.authorName__container")
    |> Enum.map(&parse_author/1)
  end

  defp parse_author(author_html) do
    %Contributor{
      id: "author:" <> parse_id(author_html, "authorName"),
      name: parse_author_name(author_html),
      type: parse_author_type(author_html)
    }
  end

  defp parse_author_name(author_html) do
    author_html |> Floki.find("span[itemprop='name']") |> Floki.text() |> clean_string()
  end

  defp parse_author_type(author_html) do
    case author_html |> Floki.find("span.greyText") |> Floki.text() do
      "" ->
        "author"

      "(Goodreads Author)" ->
        "author"

      "(Goodreads Author)(" <> rest ->
        rest |> String.slice(0..-2//1) |> String.downcase() |> clean_string()

      string ->
        string |> String.slice(1..-2//1) |> String.downcase() |> clean_string()
    end
  end

  defp parse_id(html, class) do
    [url] = html |> Floki.find("a.#{class}[itemprop='url']") |> Floki.attribute("href")
    uri = URI.parse(url)
    Path.basename(uri.path)
  end

  defp parse_thumbnail(book_html) do
    [src] = book_html |> Floki.find("img.bookCover") |> Floki.attribute("src")
    Image.fetch_from_source(src)
  end

  defp parse_work_id(book_html) do
    [url] = book_html |> Floki.find("a[href^='/work/editions/']") |> Floki.attribute("href")
    uri = URI.parse(url)
    Path.basename(uri.path)
  end

  @space ~r/\s+/
  defp clean_string(string) do
    @space
    |> Regex.replace(string, " ")
    |> String.trim()
  end
end
