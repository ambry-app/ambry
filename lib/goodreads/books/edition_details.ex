defmodule GoodReads.Books.EditionDetails do
  @moduledoc false

  alias GoodReads.{Image, Browser}

  defstruct [:id, :title, :authors, :series, :description, :cover_image]

  def edition_details("edition:" <> id = full_id) do
    with {:ok, page_html} = Browser.get_page_html("/book/show/#{id}"),
         {:ok, document} <- Floki.parse_document(page_html) do
      {:ok, parse_edition_details(full_id, document)}
    else
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_edition_details(id, html) do
    %__MODULE__{
      id: id,
      title: parse_book_title(html),
      # TODO:
      authors: [],
      series: [],
      # FIXME: parse edition published details, not "first publishes" (this is
      # already available from the editions scrape)
      # first_published: parse_first_published(html),
      description: parse_description(html),
      cover_image: parse_cover_image(html)
    }
  end

  defp parse_book_title(html) do
    html |> Floki.find("h1[data-testid='bookTitle']") |> Floki.text()
  end

  # defp parse_first_published(html) do
  #   published_text =
  #     html
  #     |> Floki.find("div.FeaturedDetails p[data-testid='publicationInfo']")
  #     |> Floki.text()

  #   case published_text do
  #     "" -> nil
  #     "First published " <> date_string -> parse_date(date_string)
  #     _else -> nil
  #   end
  # end

  # @date_regex ~r/^(.*?) ([0-9]+), ([0-9]+)$/
  # defp parse_date(date_string) do
  #   [_match, month, day, year] = Regex.run(@date_regex, date_string)
  #   Date.new!(String.to_integer(year), parse_month(month), String.to_integer(day))
  # end

  # defp parse_month("January"), do: 1
  # defp parse_month("February"), do: 2
  # defp parse_month("March"), do: 3
  # defp parse_month("April"), do: 4
  # defp parse_month("May"), do: 5
  # defp parse_month("June"), do: 6
  # defp parse_month("July"), do: 7
  # defp parse_month("August"), do: 8
  # defp parse_month("September"), do: 9
  # defp parse_month("October"), do: 10
  # defp parse_month("November"), do: 11
  # defp parse_month("December"), do: 12

  defp parse_description(html) do
    html
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

  defp parse_cover_image(html) do
    [src] = html |> Floki.find("div.BookPage__bookCover img") |> Floki.attribute("src")

    Image.fetch_from_source(src)
  end

  defp clean_string(string) do
    string
    |> String.replace("\u00a0", "")
    |> String.replace("\u201C", "\"")
    |> String.replace("\u201D", "\"")
    |> String.replace("\u2018", "'")
    |> String.replace("\u2019", "'")
    |> String.trim()
  end
end
