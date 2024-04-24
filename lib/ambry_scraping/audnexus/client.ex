defmodule AmbryScraping.Audnexus.Client do
  @moduledoc false

  require Logger

  @url "https://api.audnex.us"

  def get(path, opts \\ []) do
    url = "#{@url}#{path}"

    Logger.debug(fn -> "[Audnexus.Client] requesting #{url}" end)

    {micros, response} = :timer.tc(fn -> Req.get(url, opts) end)

    Logger.debug(fn -> "[Audnexus.Client] got response in #{micros / 1_000_000} seconds" end)

    response
  end
end
