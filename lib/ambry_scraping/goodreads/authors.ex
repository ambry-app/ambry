defmodule AmbryScraping.GoodReads.Authors do
  @moduledoc """
  GoodReads web-scraping API for authors
  """

  alias AmbryScraping.GoodReads.Books
  alias AmbryScraping.GoodReads.Browser
  alias AmbryScraping.HTMLToMD
  alias AmbryScraping.Image

  defmodule Author do
    @moduledoc false
    defstruct [:id, :name, :description, :image]
  end

  def details("author:" <> id = full_id) do
    with {:ok, author_html} <- Browser.get_page_html("/author/show/#{id}"),
         {:ok, photos_html} <- Browser.get_page_html("/photo/author/#{id}"),
         {:ok, author_document} <- Floki.parse_document(author_html),
         {:ok, photos_document} <- Floki.parse_document(photos_html) do
      parse_author_details(full_id, author_document, photos_document)
    end
  end

  defp parse_author_details(full_id, author_document, photos_document) do
    maybe_error(%Author{
      id: full_id,
      name: parse_name(author_document),
      description: parse_description(author_document),
      image: parse_image(photos_document)
    })
  end

  defp maybe_error(%{name: "", description: nil, image: nil}), do: {:error, :not_found}
  defp maybe_error(author), do: {:ok, author}

  defp parse_name(document) do
    document |> Floki.find("h1.authorName") |> Floki.text()
  end

  defp parse_description(document) do
    case Floki.find(document, "div.aboutAuthorInfo span[id^='freeText']:last-of-type") do
      [] ->
        nil

      [span] ->
        span
        |> Floki.children()
        |> HTMLToMD.html_to_md()
    end
  end

  defp parse_image(document) do
    case document |> Floki.find("ul.photoList li.profile img") |> Floki.attribute("src") do
      [src] ->
        src = String.replace(src, "p2", "p8")
        Image.fetch_from_source(src)

      _else ->
        nil
    end
  end

  def search(query) do
    with {:ok, results} <- Books.search(query) do
      downcased_query_words =
        query |> String.downcase() |> String.split(" ", trim: true) |> Enum.reject(&(String.length(&1) < 2))

      {:ok,
       results
       |> Enum.flat_map(& &1.contributors)
       |> Enum.uniq_by(& &1.id)
       |> Enum.filter(fn contributor ->
         downcased_name = String.downcase(contributor.name)
         Enum.any?(downcased_query_words, &String.contains?(downcased_name, &1))
       end)}
    end
  end
end
