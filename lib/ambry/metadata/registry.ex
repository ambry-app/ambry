defmodule Ambry.Metadata.Registry do
  @moduledoc """
  Runtime-configurable registry of metadata providers.

  The set of provider *modules* is fixed at compile time; whether each is
  enabled, its priority order, and its settings (base URL, API token, …)
  are operator-editable at runtime, persisted in `metadata_provider_configs`.
  Defaults give a zero-config working setup: every known provider enabled,
  rreading-glasses against the public instance.
  """

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.ProviderConfig
  alias Ambry.Metadata.Providers.Audible
  alias Ambry.Metadata.Providers.Audnexus
  alias Ambry.Metadata.Providers.Hardcover
  alias Ambry.Metadata.Providers.RreadingGlasses
  alias Ambry.Repo

  @known_providers [RreadingGlasses, Hardcover, Audible, Audnexus]

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
      known_keys = Enum.map(entry.module.config_fields(), &to_string(&1.key))

      config =
        attrs
        |> Map.get(:config, %{})
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.take(known_keys)

      attrs =
        attrs
        |> Map.take([:enabled, :priority])
        |> Map.put(:config, config)
        |> Map.put(:provider_id, provider_id)

      (Repo.get(ProviderConfig, provider_id) || %ProviderConfig{})
      |> ProviderConfig.changeset(attrs)
      |> Repo.insert_or_update()
    end
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
