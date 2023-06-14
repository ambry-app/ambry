defmodule GoodReads.Books.Edition do
  @moduledoc false

  alias GoodReads.Browser

  def edition("edition:" <> id) do
    with {:ok, page_html} = Browser.get_page_html("/book/show/#{id}"),
         {:ok, document} <- Floki.parse_document(page_html) do
      parse_book(id, document)
    else
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_book(id, book_html) do
    %{
      id: id,
      title: parse_book_title(book_html),
      authors: [],
      series: [],
      published: parse_first_published(book_html),
      description: parse_description(book_html)
    }
  end

  defp parse_book_title(book_html) do
    book_html |> Floki.find("h1[data-testid='bookTitle']") |> Floki.text()
  end

  defp parse_first_published(book_html) do
    published_text =
      book_html
      |> Floki.find("div.FeaturedDetails p[data-testid='publicationInfo']")
      |> Floki.text()

    case published_text do
      "" -> nil
      "First published " <> date_string -> parse_date(date_string)
      _else -> nil
    end
  end

  @date_regex ~r/^(.*?) ([0-9]+), ([0-9]+)$/
  defp parse_date(date_string) do
    [_match, month, day, year] = Regex.run(@date_regex, date_string)
    Date.new!(String.to_integer(year), parse_month(month), String.to_integer(day))
  end

  defp parse_month("January"), do: 1
  defp parse_month("February"), do: 2
  defp parse_month("March"), do: 3
  defp parse_month("April"), do: 4
  defp parse_month("May"), do: 5
  defp parse_month("June"), do: 6
  defp parse_month("July"), do: 7
  defp parse_month("August"), do: 8
  defp parse_month("September"), do: 9
  defp parse_month("October"), do: 10
  defp parse_month("November"), do: 11
  defp parse_month("December"), do: 12

  defp parse_description(book_html) do
    book_html
    |> Floki.find("div[data-testid='description'] span.Formatted")
    |> List.first()
    |> Floki.children()
    |> Floki.traverse_and_update(&description_to_markdown/1)
    |> Floki.raw_html()
    |> clean_string()
  end

  defp description_to_markdown(node) do
    case node do
      {"b", [], children} -> format_children(children, "**")
      {"i", [], children} -> format_children(children, "_")
      {"br", [], []} -> "\n"
      other -> inspect(other)
    end
  end

  defp format_children(children, wrapping),
    do: children |> Enum.join("") |> wrap(wrapping)

  defp wrap(string, wrapping), do: "#{wrapping}#{string}#{wrapping}"

  defp clean_string(string) do
    string
    |> String.replace("\n", "")
    |> String.replace("\u00a0", "")
    |> String.replace("\u201C", "\"")
    |> String.replace("\u201D", "\"")
    |> String.replace("\u2018", "'")
    |> String.replace("\u2019", "'")
    |> String.trim()
  end
end
