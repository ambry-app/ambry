defmodule Ambry.Metadata.Audible do
  @moduledoc """
  Fetch metadata from Audible's undocumented API

  Caches results in our local postgres.
  """

  import Ecto.Query

  alias Ambry.Metadata.Audible.Cache
  alias Ambry.Repo
  alias AmbryScraping.Audible.Products
  alias AmbryScraping.Audnexus.Authors
  alias AmbryScraping.Audnexus.Books

  def search_books(query, refresh \\ false)
  def search_books(query, true), do: clear_get_and_cache(query, &Products.search/1, &search_books_key/1)
  def search_books(query, false), do: cache_get(query, &Products.search/1, &search_books_key/1)

  defp search_books_key(query_string), do: "search:#{query_string}"

  def search_authors(query, refresh \\ false)
  def search_authors(query, true), do: clear_get_and_cache(query, &Authors.search/1, &search_authors_key/1)
  def search_authors(query, false), do: cache_get(query, &Authors.search/1, &search_authors_key/1)

  defp search_authors_key(query_string), do: "search_authors:#{query_string}"

  def author(asin, refresh \\ false)
  def author(asin, true), do: clear_get_and_cache(asin, &Authors.details/1)
  def author(asin, false), do: cache_get(asin, &Authors.details/1)

  def chapters(asin, refresh \\ false)
  def chapters(asin, true), do: clear_get_and_cache(asin, &Books.chapters/1)
  def chapters(asin, false), do: cache_get(asin, &Books.chapters/1)

  defp clear_get_and_cache(arg, fetch_fun, key_fun \\ &Function.identity/1) do
    Repo.delete_all(from c in Cache, where: [key: ^key_fun.(arg)])
    get_and_cache(arg, fetch_fun, key_fun)
  end

  defp cache_get(arg, fetch_fun, key_fun \\ &Function.identity/1) do
    case Repo.get(Cache, key_fun.(arg)) do
      nil -> get_and_cache(arg, fetch_fun, key_fun)
      cache -> {:ok, :erlang.binary_to_term(cache.value)}
    end
  end

  defp get_and_cache(arg, fetch_fun, key_fun) do
    case fetch_fun.(arg) do
      {:error, reason} ->
        {:error, reason}

      {:ok, result} ->
        upsert_cache_entry!(key_fun.(arg), :erlang.term_to_binary(result))
        {:ok, result}
    end
  end

  defp upsert_cache_entry!(key, value) do
    %Cache{}
    |> Cache.changeset(%{key: key, value: value})
    |> Repo.insert!(on_conflict: [set: [value: value]], conflict_target: :key)
  end
end
