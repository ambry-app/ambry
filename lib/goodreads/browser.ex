defmodule GoodReads.Browser do
  @moduledoc """
  Headless browser interface of scraping GoodReads.

  This serializes all access to the Marionette.Socket so that simultaneous
  requests can't interfere with each other.
  """

  use GenServer

  require Logger

  @url "https://www.goodreads.com"

  # Time to sleep between checking if the page has fully loaded (ms)
  @sleep_interval 100

  # Max attempts to check for fully loaded page before giving up
  @max_attempts 10

  # Total max time to wait for the GenServer call to happen (ms)
  @timeout 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_page_html(path) do
    GenServer.call(__MODULE__, {:get_page_html, path}, @timeout)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:get_page_html, path}, _from, state) do
    url = "#{@url}#{path}"
    Logger.debug(fn -> "[GoodReads.Browser] requesting #{url}" end)

    response =
      case Marionette.Socket.order("Navigate", %{url: url}) do
        %{error: nil} -> get_fully_loaded_page_source()
        %{error: error} -> {:error, inspect(error)}
      end

    {:reply, response, state}
  end

  defp get_fully_loaded_page_source(attempt \\ 0)
  defp get_fully_loaded_page_source(@max_attempts), do: {:error, :page_never_loaded}

  defp get_fully_loaded_page_source(attempt) do
    with %{error: nil, result: %{"value" => html}} <- Marionette.Socket.order("GetPageSource"),
         {:ok, document} <- Floki.parse_document(html) do
      case Floki.find(document, "svg[aria-label='Loading interface...']") do
        [] ->
          {:ok, html}

        _svgs ->
          Process.sleep(@sleep_interval)
          get_fully_loaded_page_source(attempt + 1)
      end
    else
      %{error: error} -> {:error, inspect(error)}
      {:error, error} -> {:error, error}
    end
  end
end
