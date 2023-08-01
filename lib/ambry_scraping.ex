defmodule AmbryScraping do
  @moduledoc false
  alias AmbryScraping.Marionette.Connection

  def web_scraping_available? do
    Connection
    |> Process.whereis()
    |> then(fn
      nil -> false
      pid -> Process.alive?(pid)
    end)
  end
end
