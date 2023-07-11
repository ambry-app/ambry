defmodule AmbryScraping.GoodReads.Books.EditionDetails do
  @moduledoc false

  alias AmbryScraping.GoodReads.{Browser, PublishedDate}
  alias AmbryScraping.{HTMLToMD, Image}

  defstruct [
    :id,
    :title,
    :authors,
    :series,
    :description,
    :cover_image,
    :format,
    :published,
    :publisher,
    :language
  ]

  defmodule Contributor do
    @moduledoc false
    defstruct [:id, :name, :type]
  end

  defmodule Series do
    @moduledoc false
    defstruct [:id, :name, :number]
  end

  def edition_details("edition:" <> id = full_id) do
    with {:ok, page_html} <-
           Browser.get_page_html("/book/show/#{id}",
             click: "button[aria-label='Book details and editions']",
             wait_for: "div.EditionDetails"
           ),
         {:ok, document} <- Floki.parse_document(page_html) do
      {:ok, parse_edition_details(full_id, document)}
    end
  end

  defp parse_edition_details(id, html) do
    attrs = %{
      id: id,
      title: parse_book_title(html),
      authors: parse_authors(html),
      description: parse_description(html),
      cover_image: parse_cover_image(html),
      series: []
    }

    work_details_rows = Floki.find(html, "div.WorkDetails div.DescListItem")
    edition_details_rows = Floki.find(html, "div.EditionDetails div.DescListItem")

    attrs = Enum.reduce(work_details_rows ++ edition_details_rows, attrs, &add_details/2)

    struct!(__MODULE__, attrs)
  end

  defp parse_book_title(html) do
    html |> Floki.find("h1[data-testid='bookTitle']") |> Floki.text()
  end

  defp parse_authors(html) do
    html
    |> Floki.find(".ContributorLinksList .ContributorLink")
    |> Enum.map(&parse_author/1)
  end

  defp parse_author(html) do
    name = html |> Floki.find("span[data-testid='name']") |> Floki.text() |> clean_string()
    role = html |> Floki.find("span[data-testid='role']") |> Floki.text() |> clean_string()
    type = clean_author_type_string(role)

    %Contributor{
      id: "author:" <> parse_id(html, "ContributorLink"),
      name: name,
      type: type
    }
  end

  defp clean_author_type_string(""), do: "author"

  defp clean_author_type_string(string) do
    string |> String.slice(1..-2) |> String.downcase()
  end

  defp parse_description(html) do
    html
    |> Floki.find("div[data-testid='description'] span.Formatted")
    |> List.first()
    |> Floki.children()
    |> HTMLToMD.html_to_md()
  end

  defp parse_cover_image(html) do
    [src] = html |> Floki.find("div.BookPage__bookCover img") |> Floki.attribute("src")

    Image.fetch_from_source(src)
  end

  defp add_details(row, attrs) do
    key = row |> Floki.find("dt") |> Floki.text() |> clean_string()
    value = row |> Floki.find("dd") |> Floki.text() |> clean_string()

    case key do
      "Format" ->
        Map.put(attrs, :format, value)

      "Published" ->
        {published, publisher} = parse_published(value)

        Map.merge(attrs, %{
          published: published,
          publisher: publisher
        })

      "Language" ->
        Map.put(attrs, :language, value)

      "Series" ->
        Map.put(attrs, :series, parse_series(row))

      _else ->
        attrs
    end
  end

  @published_regex ~r/^(.*?) by (.*?)$/
  defp parse_published(published_string) do
    case Regex.run(@published_regex, published_string) do
      [_match, date_string, publisher_string] ->
        {PublishedDate.new(date_string), publisher_string}

      _else ->
        {nil, nil}
    end
  end

  defp parse_series(html) do
    [series_link | rest] =
      html
      |> Floki.find("div[data-testid='contentContainer']")
      |> List.first()
      |> Floki.children()

    Enum.scan(rest, series_part(series_link), fn next_part, previous_part ->
      case series_part(next_part) do
        number when is_binary(number) -> %{previous_part | number: number}
        series -> series
      end
    end)
  end

  defp series_part({"a", _attrs, _children} = link) do
    [url] = Floki.attribute(link, "href")
    uri = URI.parse(url)
    id = Path.basename(uri.path)
    name = link |> Floki.text() |> clean_string()

    %Series{id: "series:" <> id, name: name}
  end

  @series_number_regex ~r/\(#([0-9.]+)\)/
  defp series_part(string) when is_binary(string) do
    [_match, number] = Regex.run(@series_number_regex, string)
    number
  end

  defp parse_id(html, class) do
    [url] = html |> Floki.find("a.#{class}") |> Floki.attribute("href")
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
