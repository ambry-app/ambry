defmodule AmbryScraping.Audnexus.Author do
  @moduledoc """
  Audnexus Authors API.

  FIXME: deprecated
  """

  @url "https://api.audnex.us/authors"

  def get(asin) do
    with {:ok, response} <- Req.get("#{@url}/#{asin}") do
      {:ok, response.body}
    end
  end

  def search(name) do
    with {:ok, response} <- Req.get(@url, params: [name: name]) do
      {:ok, Enum.uniq_by(response.body, & &1["asin"])}
    end
  end
end
