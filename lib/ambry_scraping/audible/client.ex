defmodule AmbryScraping.Audible.Client do
  @moduledoc false

  require Logger

  @url "https://api.audible.com/1.0"

  def get(path, params) do
    query = URI.encode_query(params)
    url = "#{@url}#{path}" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    Logger.debug(fn -> "[Audible.Client] requesting #{url}" end)

    {micros, response} = :timer.tc(fn -> Req.get(url) end)

    Logger.debug(fn -> "[Audible.Client] got response in #{micros / 1_000_000} seconds" end)

    response
  end
end
