defmodule Ambry.Metadata.Providers.Audible do
  @moduledoc """
  Recording-level metadata provider backed by Audible's catalog API.

  Wraps the existing `AmbryScraping.Audible` HTTP client (the undocumented
  but stable JSON catalog API — no browser scraping involved) and normalizes
  its results. This is the primary source for narrator credits, square
  audiobook covers, and publication facts; ASIN is the natural key.
  """

  @behaviour Ambry.Metadata.Provider

  alias Ambry.Metadata.Provider
  alias AmbryScraping.Audible

  @impl Provider
  def id, do: "audible"

  @impl Provider
  def display_name, do: "Audible"

  @impl Provider
  def level, do: :recording

  @impl Provider
  def capabilities, do: [:book_search]

  @impl Provider
  def config_fields do
    [
      %Provider.ConfigField{
        key: :language,
        label: "Language",
        type: :string,
        default: "english",
        help:
          "Only show search results in this language (Audible's language names, e.g. " <>
            ~s{"english", "german"). Set to "any" to disable filtering. } <>
            "Clear the cache after changing so old results don't linger."
      },
      %Provider.ConfigField{
        key: :marketplaces,
        label: "Marketplaces",
        type: :string,
        default: "us",
        help:
          "Which regional Audible catalogs to search, comma-separated — " <>
            "us, uk, ca, au, de, fr, es, it, in, jp. Editions are regional, so a UK-only " <>
            "recording is invisible to the US catalog. Results are merged, and the same " <>
            "recording appearing in several catalogs is collapsed. Each extra marketplace " <>
            "is another request per lookup, and a first inbox scan is hundreds of lookups."
      }
    ]
  end

  # A structured query is the whole point at this level: the catalog endpoint
  # matches `title` against the title alone, so a concatenated
  # "title author" string finds nothing — which is how the inbox's recording
  # level came up empty on every item. `narrator` is what distinguishes two
  # recordings of one work, and it's a real parameter here.
  @impl Provider
  def search_books(%Provider.Query{} = query, config), do: widen(attempts(query), config)

  def search_books(query, config) when is_binary(query), do: widen([%{keywords: query}], config)

  # Every parameter here is an AND filter, so the most precise query is also
  # the most fragile: asking for narrator "Jeff Harding" on a book whose only
  # Audible edition is read by Robertson Dean returns nothing at all, rather
  # than the edition that does exist. So the query is tried narrow first and
  # widened until something comes back — precision when precision is
  # available, recall when it isn't.
  #
  # Scoring still judges the narrator afterwards, which is what keeps a
  # widened result from being mistaken for a confident one: the wrong
  # narrator's edition comes back with a low score rather than being adopted.
  defp attempts(%Provider.Query{} = query) do
    [
      %{title: query.title, author: query.author, narrator: query.narrator},
      %{title: query.title, author: query.author},
      %{title: query.title},
      %{keywords: query.keywords || to_string(query)}
    ]
    |> Enum.map(&drop_blanks/1)
    |> Enum.reject(&(map_size(&1) == 0))
    |> Enum.uniq()
  end

  defp drop_blanks(params) do
    params |> Enum.reject(fn {_key, value} -> value in [nil, ""] end) |> Map.new()
  end

  defp widen([], _config), do: {:ok, []}

  defp widen([params | rest], config) do
    opts = [language: language(config), marketplaces: marketplaces(config)]

    case Audible.search_books(params, opts) do
      {:ok, []} -> widen(rest, config)
      {:ok, products} -> {:ok, Enum.map(products, &product_to_book/1)}
      # A failure is not an empty result — widening past it would hide an
      # outage behind a vaguer query that happens to succeed.
      {:error, reason} -> {:error, reason}
    end
  end

  defp language(config), do: config[:language] || "english"

  defp marketplaces(config), do: Audible.parse_marketplaces(config[:marketplaces])

  defp product_to_book(product) do
    %Provider.Book{
      provider: id(),
      id: product.id,
      asin: product.id,
      title: product.title,
      description: product.description,
      cover_url: product.cover_image,
      published: published(product.published),
      publisher: product.publisher,
      language: product.language,
      format: product.format,
      authors:
        Enum.map(product.authors, fn author ->
          %Provider.Contributor{id: author.id, name: author.name, role: "author"}
        end),
      narrators:
        Enum.map(product.narrators, fn narrator ->
          %Provider.Contributor{id: nil, name: narrator.name, role: "narrator"}
        end),
      series:
        Enum.map(product.series, fn series ->
          %Provider.Series{id: series.id, name: series.title, number: series.sequence}
        end)
    }
  end

  defp published(nil), do: nil
  defp published(%Date{} = date), do: %Provider.PublishedDate{date: date, display_format: :full}
end
