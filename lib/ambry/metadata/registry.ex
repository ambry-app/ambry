defmodule Ambry.Metadata.Registry do
  @moduledoc """
  Runtime-configurable registry of metadata providers.

  The set of provider *modules* is fixed at compile time; whether each is
  enabled, its priority order, and its settings (base URL, API token, …)
  are operator-editable at runtime, persisted in `metadata_provider_configs`.
  Defaults give a zero-config working setup: every known provider enabled,
  rreading-glasses against the public instance.
  """

  alias Ambry.Metadata.Cache
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.ProviderConfig
  alias Ambry.Metadata.Providers.Audible
  alias Ambry.Metadata.Providers.Audnexus
  alias Ambry.Metadata.Providers.Hardcover
  alias Ambry.Metadata.Providers.RreadingGlasses
  alias Ambry.Metadata.Providers.Tmdb
  alias Ambry.Metadata.Providers.Wikidata
  alias Ambry.Repo

  @known_providers [RreadingGlasses, Hardcover, Audible, Audnexus, Wikidata, Tmdb]

  defmodule Entry do
    @moduledoc "A provider module joined with its runtime configuration."
    defstruct [
      :module,
      :id,
      :display_name,
      :level,
      :capabilities,
      :enabled,
      :available,
      :priority,
      :config
    ]
  end

  @doc "All known providers with their runtime configuration, in priority order."
  def all do
    stored = Repo.all(ProviderConfig)

    @known_providers
    |> Enum.with_index()
    |> Enum.map(fn {module, index} ->
      row = Enum.find(stored, &(&1.provider_id == module.id()))
      config = build_config(module, row)

      %Entry{
        module: module,
        id: module.id(),
        display_name: module.display_name(),
        level: module.level(),
        capabilities: module.capabilities(),
        enabled: if(row, do: row.enabled, else: true),
        available: Provider.available?(module, config),
        priority: (row && row.priority) || index,
        config: config
      }
    end)
    |> Enum.sort_by(& &1.priority)
  end

  @doc "Enabled *and* available providers, optionally filtered by level or capability."
  def enabled(filters \\ []) do
    level = Keyword.get(filters, :level)
    capability = Keyword.get(filters, :capability)

    Enum.filter(all(), fn entry ->
      entry.enabled and entry.available and
        (is_nil(level) or entry.level == level) and
        (is_nil(capability) or capability in entry.capabilities)
    end)
  end

  @doc "Fetches a provider entry by its string id."
  def fetch(provider_id) do
    case Enum.find(all(), &(&1.id == provider_id)) do
      nil -> {:error, :unknown_provider}
      entry -> {:ok, entry}
    end
  end

  @doc """
  Upserts the stored settings for a provider. Accepts `:enabled`,
  `:priority`, and `:config` (a map of field-key => value; only keys the
  provider declares in `config_fields/0` are kept).
  """
  def update(provider_id, attrs) do
    with {:ok, entry} <- fetch(provider_id) do
      row = Repo.get(ProviderConfig, provider_id) || %ProviderConfig{}
      changes = changes(entry, row, attrs, provider_id)

      row
      |> ProviderConfig.changeset(changes)
      |> Repo.insert_or_update()
      |> tap(fn
        {:ok, _saved} -> forget_stale_answers(provider_id, row, changes)
        _failed -> :ok
      end)
    end
  end

  # **A cached answer was given under the settings in force when it was
  # cached.** The cache keys on the provider and the question and nothing
  # else, so changing what a provider is *asked* (which languages count, which
  # regional catalogs to search) would leave every question already asked
  # answering the previous way for the rest of its TTL, a week for searches.
  #
  # Emptied on a config change rather than keyed on the config: a key that
  # carries the settings never *forgets* the superseded answers, it just stops
  # finding them, and the rows sit in Postgres until their TTL expires.
  # Enabling, disabling and reordering leave it alone — none of them changes
  # what a question means.
  defp forget_stale_answers(provider_id, row, changes) do
    case Map.fetch(changes, :config) do
      {:ok, config} when config != %{} ->
        if config != (row.config || %{}), do: Cache.clear_provider(provider_id)

      _unchanged ->
        :ok
    end
  end

  # Settings the caller didn't mention are left alone. This is not a detail:
  # writing an empty config on every update meant that merely reordering
  # providers — or toggling one off and on — silently destroyed the operator's
  # API token, and the only symptom was a provider quietly going unavailable
  # later.
  defp changes(entry, row, attrs, provider_id) do
    changes =
      attrs
      |> Map.take([:enabled, :priority])
      |> Map.put(:provider_id, provider_id)

    case Map.fetch(attrs, :config) do
      :error -> changes
      {:ok, config} -> Map.put(changes, :config, merged_config(entry, row, config))
    end
  end

  # Supplied keys win; unsupplied ones keep whatever was stored, so a partial
  # update can't clear a field it never mentioned. Clearing stays possible by
  # sending the field empty — `build_config/2` reads "" as "use the default".
  defp merged_config(entry, row, config) do
    known_keys = Enum.map(entry.module.config_fields(), &to_string(&1.key))

    supplied =
      config
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.take(known_keys)

    row.config |> Kernel.||(%{}) |> Map.merge(supplied)
  end

  defp build_config(module, row) do
    defaults = Provider.default_config(module)
    stored = (row && row.config) || %{}

    Map.new(defaults, fn {key, default} ->
      case Map.get(stored, to_string(key)) do
        nil -> {key, default}
        "" -> {key, default}
        value -> {key, value}
      end
    end)
  end
end
