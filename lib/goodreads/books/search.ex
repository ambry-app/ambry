defmodule GoodReads.Books.Search do
  @moduledoc false

  alias GoodReads.Browser

  @series_regex ~r/^.*?(?:\(([^()]+?),?\s+#([-0-9.]+)\))?$/
  @space ~r/\s+/

  defmodule Book do
    defstruct [:id, :title, :authors, :series, :most_reviewed_edition_id]
  end

  defmodule Contributor do
    defstruct [:id, :name, :type]
  end

  defmodule Series do
    defstruct [:name, :number]
  end

  def search(query) do
    query = URI.encode_query(%{utf8: "✓", query: query})
    path = "/search" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    with {:ok, page_html} = Browser.get_page_html(path),
         {:ok, document} <- Floki.parse_document(page_html) do
      parse_books(document)
    else
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
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
      authors: parse_authors(book_html),
      series: parse_series(book_html),
      most_reviewed_edition_id: "edition:" <> parse_id(book_html, "bookTitle")
    }
  end

  defp parse_book_title(book_html) do
    [title] = book_html |> Floki.find("td:first-child a") |> Floki.attribute("title")
    clean_string(title)
  end

  defp parse_series(book_html) do
    title_with_maybe_series =
      book_html |> Floki.find("a.bookTitle span[itemprop='name']") |> Floki.text()

    case Regex.run(@series_regex, title_with_maybe_series) do
      [_match] -> nil
      [_match, series, number] -> %Series{name: clean_string(series), number: number}
    end
  end

  defp parse_authors(book_html) do
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
      "" -> "author"
      "(Goodreads Author)" -> "author"
      string -> string |> String.slice(1..-2) |> String.downcase()
    end
  end

  defp parse_id(html, class) do
    [url] = html |> Floki.find("a.#{class}[itemprop='url']") |> Floki.attribute("href")
    uri = URI.parse(url)
    uri.path |> Path.basename()
  end

  defp parse_work_id(book_html) do
    [url] = book_html |> Floki.find("a[href^='/work/editions/']") |> Floki.attribute("href")
    uri = URI.parse(url)
    uri.path |> Path.basename()
  end

  defp clean_string(string) do
    @space
    |> Regex.replace(string, " ")
    |> String.trim()
  end
end
