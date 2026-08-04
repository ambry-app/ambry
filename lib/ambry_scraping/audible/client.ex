defmodule AmbryScraping.Audible.Client do
  @moduledoc false

  require Logger

  # Audible's catalog is regional, and an edition existing in one marketplace
  # says nothing about the others — Neuromancer read by Jeff Harding is a UK
  # title and simply is not in the US catalog. The default stays US-only so
  # nothing changes for an operator who never asks for more; the inbox widens
  # it per the provider's configuration.
  @marketplaces %{
    "us" => "https://api.audible.com/1.0",
    "uk" => "https://api.audible.co.uk/1.0",
    "ca" => "https://api.audible.ca/1.0",
    "au" => "https://api.audible.com.au/1.0",
    "de" => "https://api.audible.de/1.0",
    "fr" => "https://api.audible.fr/1.0",
    "es" => "https://api.audible.es/1.0",
    "it" => "https://api.audible.it/1.0",
    "in" => "https://api.audible.in/1.0",
    "jp" => "https://api.audible.co.jp/1.0"
  }

  @default_marketplace "us"

  @doc "The marketplace codes this client knows how to reach."
  def marketplaces, do: Map.keys(@marketplaces)

  @doc "What to search when the operator hasn't said otherwise."
  def default_marketplaces, do: [@default_marketplace]

  @doc """
  Parses an operator's marketplace setting into a list of codes.

  Unknown codes are dropped rather than attempted — a typo should cost that
  one marketplace, not the whole search — and an empty result falls back to
  the default so a bad setting can never silently disable Audible entirely.
  """
  def parse_marketplaces(nil), do: default_marketplaces()

  def parse_marketplaces(setting) when is_binary(setting) do
    codes =
      setting
      |> String.split([",", " "], trim: true)
      |> Enum.map(&String.downcase(String.trim(&1)))
      |> Enum.filter(&Map.has_key?(@marketplaces, &1))
      |> Enum.uniq()

    if codes == [], do: default_marketplaces(), else: codes
  end

  def parse_marketplaces(codes) when is_list(codes),
    do: codes |> Enum.join(",") |> parse_marketplaces()

  def get(path, params, opts \\ []) do
    marketplace = Keyword.get(opts, :marketplace, @default_marketplace)
    base = Map.get(@marketplaces, marketplace, @marketplaces[@default_marketplace])

    query = URI.encode_query(params)
    url = "#{base}#{path}" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    Logger.debug(fn -> "[Audible.Client] requesting #{url}" end)

    {micros, response} = :timer.tc(fn -> Req.get(url) end)

    Logger.debug(fn -> "[Audible.Client] got response in #{micros / 1_000_000} seconds" end)

    response
  end
end
