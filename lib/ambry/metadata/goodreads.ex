defmodule Ambry.Metadata.GoodReads do
  @moduledoc """
  Fetch metadata from GoodReads by scraping

  Caches results in our local postgres.
  """

  import Ecto.Query

  alias Ambry.Metadata.GoodReads.Cache
  alias Ambry.Repo
  alias AmbryScraping.GoodReads.Authors
  alias AmbryScraping.GoodReads.Books

  def search_books(query, refresh \\ false)

  def search_books(query, true),
    do: clear_get_and_cache(query, &Books.search/1, &search_books_key/1)

  def search_books(query, false), do: cache_get(query, &Books.search/1, &search_books_key/1)

  defp search_books_key(query_string), do: "search_books:#{query_string}"

  def editions(id, refresh \\ false)
  def editions(id, true), do: clear_get_and_cache(id, &Books.editions/1)
  def editions(id, false), do: cache_get(id, &Books.editions/1)

  def edition_details(id, refresh \\ false)
  def edition_details(id, true), do: clear_get_and_cache(id, &Books.edition_details/1)
  def edition_details(id, false), do: cache_get(id, &Books.edition_details/1)

  def search_authors(query, refresh \\ false)

  def search_authors(query, true),
    do: clear_get_and_cache(query, &Authors.search/1, &search_authors_key/1)

  def search_authors(query, false), do: cache_get(query, &Authors.search/1, &search_authors_key/1)

  defp search_authors_key(query_string), do: "search_authors:#{query_string}"

  def author(id, refresh \\ false)
  def author(id, true), do: clear_get_and_cache(id, &Authors.details/1)
  def author(id, false), do: cache_get(id, &Authors.details/1)

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
