defmodule Ambry.Metadata.Providers.Audible do
  @moduledoc """
  Recording-level metadata provider backed by Audible's catalog API.

  Wraps the existing `AmbryScraping.Audible` HTTP client (the undocumented
  but stable JSON catalog API — no browser scraping involved) and normalizes
  its results. Its search answers with recordings directly, and those records
  carry narrator credits, square covers, publication facts and an ASIN.

  It is **not** a primary or preferred source, and nothing should treat it as
  one: providers are selected by the capabilities they declare, and every
  provider that can answer a question gets asked. What this one is good at is
  a fact about its records, not a rank — and it is blind in its own way, being
  a storefront rather than a bibliography: it carries preorders and drops what
  it has delisted.
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
  def capabilities, do: [:book_search, :book_details]

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
            ~s{"english", "german"). Set to "any" to disable filtering.}
      },
      %Provider.ConfigField{
        key: :marketplaces,
        label: "Marketplaces",
        type: :string,
        default: "us",
        help:
          "Which regional Audible catalogs to search, comma-separated: " <>
            "us, uk, ca, au, de, fr, es, it, in, jp. Editions are regional, so a UK-only " <>
            "recording is invisible to the US catalog. Results are merged, and the same " <>
            "recording appearing in several catalogs is collapsed. Most books are sold in " <>
            "every region, so widening often changes nothing. Each extra marketplace is " <>
            "another request per lookup, and a first inbox scan is hundreds of lookups."
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

  @doc """
  One recording, by the id its own search handed out.

  Which for this provider is an ASIN, and an ASIN is marketplace-scoped: the
  catalog that issued it is the only one that can resolve it. `:not_found` is
  a real answer here, not a failure — a storefront delists, and a recording it
  no longer sells is one it can no longer be asked about, which is exactly
  what a bibliography is for.
  """
  @impl Provider
  def book_details(asin, config) do
    case Audible.book_details(asin, marketplaces: marketplaces(config)) do
      {:ok, product} -> {:ok, product_to_book(product)}
      {:error, reason} -> {:error, reason}
    end
  end

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
      # Some catalogs answered and some did not. The answer is usable and
      # incomplete, and saying only the first half is what let a region that
      # was rate-limited read as a region with nothing in it.
      {:partial, products, reason} -> {:partial, Enum.map(products, &product_to_book/1), reason}
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
      duration_seconds: product.duration_seconds,
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
