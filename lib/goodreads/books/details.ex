defmodule GoodReads.Books.Details do
  @moduledoc false

  alias GoodReads.Browser

  defmodule Book do
    defstruct [:id, :title, :primary_author, :first_published]
  end

  def details("work:" <> id = full_id) do
    query = URI.encode_query(%{utf8: "✓", per_page: 100})
    path = "/work/editions/#{id}" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    with {:ok, page_html} = Browser.get_page_html(path),
         {:ok, document} <- Floki.parse_document(page_html) do
      parse_details(full_id, document)
    else
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_details(id, html) do
    %Book{
      id: id,
      title: parse_book_title(html),
      primary_author: parse_primary_author(html),
      first_published: parse_first_published(html)
    }
  end

  defp parse_book_title(html) do
    html |> Floki.find("h1 a") |> Floki.text()
  end

  defp parse_primary_author(html) do
    html |> Floki.find("div.workEditions h2 a") |> Floki.text()
  end

  defp parse_first_published(html) do
    published_text = html |> Floki.find("span.originalPubDate") |> Floki.text() |> String.trim()

    case published_text do
      "" -> nil
      "First published " <> date_string -> parse_date(date_string)
      _else -> nil
    end
  end

  @date_regex ~r/^(.*?) ([0-9]+).*? ([0-9]+)$/
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
end
