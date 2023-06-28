defmodule Ambry.Metadata.Audible do
  @moduledoc """
  Fetch metadata from Audible's undocumented API

  Caches results in our local postgres.
  """

  import Ecto.Query

  alias Ambry.Metadata.Audible.Cache
  alias Ambry.Repo

  alias Audible.Products

  def search(query, refresh \\ false)
  def search(query, true), do: clear_get_and_cache(query, &Products.search/1, &search_key/1)
  def search(query, false), do: cache_get(query, &Products.search/1, &search_key/1)

  defp search_key(query_string), do: "search:#{query_string}"

  defp clear_get_and_cache(arg, fetch_fun, key_fun) do
    Repo.delete_all(from c in Cache, where: [key: ^key_fun.(arg)])
    get_and_cache(arg, fetch_fun, key_fun)
  end

  defp cache_get(arg, fetch_fun, key_fun) do
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
        %Cache{}
        |> Cache.changeset(%{key: key_fun.(arg), value: :erlang.term_to_binary(result)})
        |> Repo.insert!()

        {:ok, result}
    end
  end
end
