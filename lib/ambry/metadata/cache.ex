defmodule Ambry.Metadata.Cache do
  @moduledoc """
  Postgres-backed cache for metadata-provider responses, with TTL.

  Keys are namespaced by the caller (`"provider_id:operation:arg"`), values
  are `:erlang.term_to_binary` of normalized provider structs. Entries past
  their TTL are re-fetched on read; if the re-fetch fails but a stale entry
  exists, the stale value is served (sources are disposable feeders — a dead
  provider should degrade us to stale data, not to errors).
  """

  import Ecto.Query

  alias Ambry.Repo

  require Logger

  defmodule Entry do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key {:key, :string, []}
    schema "metadata_cache" do
      field :value, :binary
      field :cached_at, :utc_datetime
    end

    def changeset(entry, attrs) do
      entry
      |> cast(attrs, [:key, :value, :cached_at])
      |> validate_required([:key, :value, :cached_at])
    end
  end

  @doc """
  Returns the cached value for `key`, or runs `fetch_fun` and caches its
  `{:ok, value}` result.

  Options:

    * `:ttl` — seconds before an entry is considered stale (default 30 days)
    * `:refresh` — bypass the cache and fetch fresh (stale fallback still
      applies if the fetch fails)
  """
  def fetch(key, fetch_fun, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, 30 * 24 * 60 * 60)
    refresh = Keyword.get(opts, :refresh, false)
    entry = Repo.get(Entry, key)

    cond do
      is_nil(entry) -> fetch_and_store(key, fetch_fun, nil)
      refresh or stale?(entry, ttl) -> fetch_and_store(key, fetch_fun, entry)
      true -> {:ok, decode(entry)}
    end
  end

  @doc "Deletes every cached entry for the given provider id."
  def clear_provider(provider_id) do
    Repo.delete_all(from e in Entry, where: like(e.key, ^"#{provider_id}:%"))
  end

  defp stale?(entry, ttl) do
    DateTime.diff(DateTime.utc_now(), entry.cached_at) > ttl
  end

  defp fetch_and_store(key, fetch_fun, stale_entry) do
    case fetch_fun.() do
      {:ok, value} ->
        store!(key, value)
        {:ok, value}

      # Never stored: a partial answer is part of an outage, and caching it
      # would keep serving the half that answered for the whole TTL. Passed
      # through rather than dropped, because the half that did answer is
      # worth having now — the caller records the miss and can ask again.
      {:partial, value, reason} ->
        Logger.warning("metadata fetch partial for #{key}: #{inspect(reason)}")
        {:partial, value, reason}

      {:error, reason} when not is_nil(stale_entry) ->
        Logger.warning("metadata fetch failed for #{key}, serving stale: #{inspect(reason)}")
        {:ok, decode(stale_entry)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store!(key, value) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    binary = :erlang.term_to_binary(value)

    %Entry{}
    |> Entry.changeset(%{key: key, value: binary, cached_at: now})
    |> Repo.insert!(
      on_conflict: [set: [value: binary, cached_at: now]],
      conflict_target: :key
    )
  end

  defp decode(entry), do: :erlang.binary_to_term(entry.value)
end
