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
      }
    ]
  end

  @impl Provider
  def search_books(query, config) do
    with {:ok, products} <- Audible.search_books(query, language: language(config)) do
      {:ok, Enum.map(products, &product_to_book/1)}
    end
  end

  defp language(config), do: config[:language] || "english"

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
