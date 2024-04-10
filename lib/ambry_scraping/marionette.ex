defmodule AmbryScraping.Marionette do
  @moduledoc false

  use Boundary, exports: [Browser]
  use Supervisor

  alias AmbryScraping.Marionette.Browser
  alias AmbryScraping.Marionette.Connection

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    case Application.fetch_env(:ambry, Connection) do
      :error ->
        :ignore

      {:ok, config} ->
        children = [
          # Connection for sending commands to the browser
          {Connection, config},
          # Higher-level interface for serializing commands to the browser
          Browser
        ]

        Supervisor.init(children, strategy: :rest_for_one)
    end
  end

  @doc """
  Checks if the web scraping service is available.

  GoodReads depends on web scraping; if this returns false then GoodReads
  scraping will not be available. Audible and Audnexus will still be available.
  """
  def web_scraping_available? do
    Connection
    |> Process.whereis()
    |> then(fn
      nil -> false
      pid -> Process.alive?(pid)
    end)
  end
end
