defmodule Ambry.Metadata.Providers do
  @moduledoc """
  Public API for querying metadata providers.

  This is the seam the web layer talks to: it resolves the provider through
  the runtime registry, routes the call through the TTL cache, and returns
  normalized `Ambry.Metadata.Provider` structs. Pass `refresh: true` to
  bypass the cache (the "re-fetch" button).

  Ambry *snapshots* provider data into its own records at import time — this
  cache exists to make interactive search/import pleasant and to be polite
  to shared public instances, not as a live link to any provider.
  """

  alias Ambry.Metadata.Cache
  alias Ambry.Metadata.Registry

  @search_ttl 7 * 24 * 60 * 60
  @details_ttl 30 * 24 * 60 * 60

  def search_books(provider_id, query, opts \\ []),
    do: call(provider_id, :book_search, :search_books, query, @search_ttl, opts)

  def book_details(provider_id, work_id, opts \\ []),
    do: call(provider_id, :book_details, :book_details, work_id, @details_ttl, opts)

  def search_authors(provider_id, query, opts \\ []),
    do: call(provider_id, :author_search, :search_authors, query, @search_ttl, opts)

  def author_details(provider_id, author_id, opts \\ []),
    do: call(provider_id, :author_details, :author_details, author_id, @details_ttl, opts)

  def chapters(provider_id, asin, opts \\ []),
    do: call(provider_id, :chapters, :chapters, asin, @details_ttl, opts)

  @doc "Clears all cached responses for a provider."
  def clear_cache(provider_id), do: Cache.clear_provider(provider_id)

  defp call(provider_id, capability, fun, arg, ttl, opts) do
    with {:ok, entry} <- Registry.fetch(provider_id),
         :ok <- check_enabled(entry),
         :ok <- check_capability(entry, capability) do
      Cache.fetch(
        "#{entry.id}:#{fun}:#{arg}",
        fn -> apply(entry.module, fun, [arg, entry.config]) end,
        ttl: ttl,
        refresh: Keyword.get(opts, :refresh, false)
      )
    end
  end

  defp check_enabled(%{enabled: true}), do: :ok
  defp check_enabled(_entry), do: {:error, :provider_disabled}

  defp check_capability(entry, capability) do
    if capability in entry.capabilities do
      :ok
    else
      {:error, :unsupported_capability}
    end
  end
end
