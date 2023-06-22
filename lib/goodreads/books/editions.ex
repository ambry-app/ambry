defmodule GoodReads.Books.Editions do
  @moduledoc false

  alias GoodReads.{Browser, Image, PublishedDate}

  defstruct [:id, :title, :primary_author, :first_published, :editions]

  defmodule Contributor do
    defstruct [:id, :name, :type]
  end

  defmodule Edition do
    defstruct [
      :id,
      :title,
      :published,
      :publisher,
      :format,
      :contributors,
      :language,
      :thumbnail
      # Possible future improvements:
      # :isbn
      # :isbn10
      # :asin
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
      "First published " <> date_string -> date_string |> clean_string() |> PublishedDate.new()
      _else -> nil
    end
  end

  defp parse_editions(html) do
    html
    |> Floki.find("div.workEditions div.elementList")
    |> Enum.flat_map(&parse_edition/1)
  end

  defp parse_edition(edition_html) do
    case Floki.find(edition_html, "div.editionData > div.dataRow") do
      [title_html, published_html, format_html, _action] ->
        extra_data_rows = Floki.find(edition_html, "div.editionData div.moreDetails div.dataRow")

        {published, publisher} = parse_published(published_html)

        [
          %Edition{
            id: "edition:" <> parse_id(edition_html, "bookTitle"),
            title: parse_edition_title(title_html),
            published: published,
            publisher: publisher,
            format: parse_format(format_html),
            contributors: parse_authors(extra_data_rows),
            language: parse_language(extra_data_rows),
            thumbnail: parse_thumbnail(edition_html)
          }
        ]

      _else ->
        # NOTE: we're throwing away editions that don't have 3 data rows
        # initially visible; they are likely low-quality and not useful
        []
    end
  end

  defp parse_edition_title(title_html) do
    title_html |> Floki.find("a.bookTitle") |> Floki.text() |> clean_string()
  end

  @published_regex ~r/^Published (.*?) by (.*?)$/
  defp parse_published(published_html) do
    string = published_html |> Floki.text() |> clean_string()

    case Regex.run(@published_regex, string) do
      [_match, date_string, publisher_string] ->
        {PublishedDate.new(date_string), publisher_string}

      _else ->
        {nil, nil}
    end
  end

  defp parse_format(format_html), do: format_html |> Floki.text() |> clean_string()

  defp parse_thumbnail(edition_html) do
    [src] = edition_html |> Floki.find("div.leftAlignedImage img") |> Floki.attribute("src")
    Image.fetch_from_source(src)
  end

  defp parse_authors(data_rows) do
    authors_row =
      Enum.find(data_rows, fn row -> Floki.find(row, ".dataTitle:fl-contains('Author')") != [] end)

    case authors_row do
      nil ->
        []

      row ->
        row
        |> Floki.find(".dataValue span[itemprop='author'] .authorName__container")
        |> Enum.map(&parse_author/1)
    end
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
    case author_html |> Floki.find("span.greyText") |> Floki.text() |> clean_string() do
      "" -> "author"
      "(Goodreads Author)" -> "author"
      "(Goodreads Author)" <> string -> clean_author_type_string(string)
      string -> clean_author_type_string(string)
    end
  end

  defp clean_author_type_string(string) do
    string |> String.slice(1..-2) |> String.downcase()
  end

  defp parse_language(data_rows) do
    language_row =
      Enum.find(data_rows, fn row ->
        Floki.find(row, ".dataTitle:fl-contains('Edition language')") != []
      end)

    case language_row do
      nil -> nil
      row -> row |> Floki.find(".dataValue") |> Floki.text() |> clean_string()
    end
  end

  defp parse_id(html, class) do
    [url] = html |> Floki.find("a.#{class}") |> Floki.attribute("href")
    uri = URI.parse(url)
    uri.path |> Path.basename()
  end

  @space ~r/\s+/
  defp clean_string(string) do
    @space
    |> Regex.replace(string, " ")
    |> String.trim()
  end
end
