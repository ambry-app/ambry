defmodule GoodReads.Books.Editions do
  @moduledoc false

  alias GoodReads.{Image, Browser}

  defstruct [:id, :title, :primary_author, :first_published, :editions]

  defmodule Contributor do
    defstruct [:id, :name, :type]
  end

  defmodule Edition do
    defstruct [
      :id,
      :title,
      :published,
      :format,
      :contributors,
      :isbn,
      :isbn10,
      :asin,
      :language,
      :thumbnail
    ]
  end

  def editions("work:" <> id = full_id) do
    query = URI.encode_query(%{utf8: "✓", per_page: 100})
    path = "/work/editions/#{id}" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    with {:ok, page_html} = Browser.get_page_html(path),
         {:ok, document} <- Floki.parse_document(page_html) do
      {:ok, parse_page(full_id, document)}
    else
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_page(id, html) do
    %__MODULE__{
      id: id,
      title: parse_book_title(html),
      primary_author: parse_primary_author(html),
      first_published: parse_first_published(html),
      editions: parse_editions(html)
    }
  end

  defp parse_book_title(html) do
    html |> Floki.find("h1 a") |> Floki.text()
  end

  defp parse_primary_author(html) do
    name = html |> Floki.find("div.workEditions h2 a") |> Floki.text()

    [url] = html |> Floki.find("div.workEditions h2 a") |> Floki.attribute("href")
    uri = URI.parse(url)
    id = "author:" <> (uri.path |> Path.basename())

    %Contributor{
      id: id,
      name: name,
      type: "primary"
    }
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

  defp parse_editions(html) do
    html
    |> Floki.find("div.workEditions div.elementList")
    |> Enum.flat_map(&parse_edition/1)
  end

  defp parse_edition(edition_html) do
    case Floki.find(edition_html, "div.editionData > div.dataRow") do
      [title_html, publisher_html, format_html, _action] ->
        _extra_data_rows = Floki.find(edition_html, "div.editionData div.moreDetails div.dataRow")

        [
          %Edition{
            id: parse_edition_id(edition_html),
            title: parse_edition_title(title_html),
            published: parse_published(publisher_html),
            format: parse_format(format_html),
            # TODO:
            contributors: nil,
            isbn: nil,
            isbn10: nil,
            asin: nil,
            language: nil,
            thumbnail: parse_thumbnail(edition_html)
          }
        ]

      _else ->
        # NOTE: we're throwing away editions that don't have 3 data rows
        # initially visible; they are likely low-quality and not useful
        []
    end
  end

  defp parse_edition_id(edition_html) do
    [url] = edition_html |> Floki.find("a.bookTitle") |> Floki.attribute("href")
    uri = URI.parse(url)
    "edition:" <> (uri.path |> Path.basename())
  end

  defp parse_edition_title(title_html) do
    title_html |> Floki.find("a.bookTitle") |> Floki.text() |> clean_string()
  end

  defp parse_published(publisher_html), do: publisher_html |> Floki.text() |> clean_string()
  defp parse_format(format_html), do: format_html |> Floki.text() |> clean_string()

  defp parse_thumbnail(edition_html) do
    [src] = edition_html |> Floki.find("div.leftAlignedImage img") |> Floki.attribute("src")
    Image.fetch_from_source(src)
  end

  @space ~r/\s+/
  defp clean_string(string) do
    @space
    |> Regex.replace(string, " ")
    |> String.trim()
  end
end
