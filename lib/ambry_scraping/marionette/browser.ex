defmodule AmbryScraping.Marionette.Browser do
  @moduledoc """
  Headless browser interface for web-scraping.

  This serializes all access to the headless browser so that simultaneous
  requests can't interfere with each other.
  """

  use GenServer

  alias AmbryScraping.Marionette.Connection

  require Logger

  # Time to sleep between checking if the page has fully loaded (ms)
  @sleep_interval 250

  # Max attempts to while waiting for actions to complete
  @max_attempts 10

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns the full page HTML of the given URL after having performed the given
  actions.
  """
  def get_page_html(url, actions \\ []) do
    GenServer.call(__MODULE__, {:get_page_html, url, actions}, :infinity)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:get_page_html, url, actions}, _from, state) do
    Logger.debug(fn -> "[Marionette.Browser] requesting #{url}" end)

    {micros, response} =
      :timer.tc(fn ->
        with :ok <- navigate(url), do: process_page(actions)
      end)

    Logger.debug(fn -> "[Marionette.Browser] got response in #{micros / 1_000_000} seconds" end)

    {:reply, response, state}
  end

  defp process_page(actions) do
    with :ok <- perform_actions(actions) do
      get_page_source()
    end
  end

  defp perform_actions([]), do: :ok

  defp perform_actions([{:wait_for_no, selector} | rest]) do
    case wait_for_no(selector) do
      :ok ->
        perform_actions(rest)

      error ->
        Logger.warning(fn ->
          "[Marionette.Browser] action {:wait_for_no, #{selector}} failed: #{inspect(error)}"
        end)

        {:error, :wait_for_no_failed}
    end
  end

  defp perform_actions([{:maybe_click, selector} | rest]) do
    with {:ok, [element_id]} <- find_elements(selector),
         :ok <- try_click(element_id) do
      perform_actions(rest)
    else
      {:ok, []} ->
        perform_actions(rest)

      {:ok, [_element | _rest]} ->
        Logger.warning(fn ->
          "[Marionette.Browser] action {:maybe_click, #{selector}} failed: found more than one element"
        end)

        {:error, :maybe_click_failed}

      error ->
        Logger.warning(fn ->
          "[Marionette.Browser] action {:maybe_click, #{selector}} failed: #{inspect(error)}"
        end)

        {:error, :maybe_click_failed}
    end
  end

  defp perform_actions([{:click, selector} | rest]) do
    with {:ok, [element_id]} <- find_elements(selector),
         :ok <- try_click(element_id) do
      perform_actions(rest)
    else
      {:ok, []} ->
        Logger.warning(fn ->
          "[Marionette.Browser] action {:click, #{selector}} failed: found no such element"
        end)

        {:error, :click_failed}

      {:ok, [_element | _rest]} ->
        Logger.warning(fn ->
          "[Marionette.Browser] action {:click, #{selector}} failed: found more than one element"
        end)

        {:error, :click_failed}

      error ->
        Logger.warning(fn ->
          "[Marionette.Browser] action {:click, #{selector}} failed: #{inspect(error)}"
        end)

        {:error, :click_failed}
    end
  end

  defp perform_actions([{:wait_for, selector} | rest]) do
    case wait_for(selector) do
      :ok ->
        perform_actions(rest)

      error ->
        Logger.warning(fn ->
          "[Marionette.Browser] action {:wait_for, #{selector}} failed: #{inspect(error)}"
        end)

        {:error, :wait_for_failed}
    end
  end

  ### Attempt Helpers

  defp wait_for_no(selector, attempt \\ 0)
  defp wait_for_no(_selector, @max_attempts), do: {:error, :max_attempts_reached}

  defp wait_for_no(selector, attempt) do
    case find_elements(selector) do
      {:ok, [_element | _rest]} ->
        Process.sleep(@sleep_interval)
        wait_for_no(selector, attempt + 1)

      {:ok, []} ->
        :ok
    end
  end

  defp wait_for(selector, attempt \\ 0)
  defp wait_for(_selector, @max_attempts), do: {:error, :max_attempts_reached}

  defp wait_for(selector, attempt) do
    case find_elements(selector) do
      {:ok, [_element | _rest]} ->
        :ok

      {:ok, []} ->
        Process.sleep(@sleep_interval)
        wait_for(selector, attempt + 1)
    end
  end

  defp try_click(element_id, attempt \\ 0)
  defp try_click(_element_id, @max_attempts), do: {:error, :max_attempts_reached}

  defp try_click(element_id, attempt) do
    case click(element_id) do
      :ok ->
        :ok

      :scrolling ->
        Process.sleep(@sleep_interval)
        try_click(element_id, attempt + 1)

      {:error, :click_failed} ->
        {:error, :click_failed}
    end
  end

  ### Connection Orders

  defp navigate(url) do
    case Connection.order("Navigate", %{url: url}) do
      {:ok, %{error: nil}} ->
        :ok

      error ->
        Logger.warning(fn -> "[Marionette.Browser] Navigate failed: #{inspect(error)}" end)
        {:error, :navigate_failed}
    end
  end

  defp get_page_source do
    case Connection.order("GetPageSource") do
      {:ok, %{error: nil, result: %{"value" => html}}} ->
        {:ok, html}

      error ->
        Logger.warning(fn -> "[Marionette.Browser] GetPageSource failed: #{inspect(error)}" end)
        {:error, :get_page_source_failed}
    end
  end

  defp find_elements(selector) do
    case Connection.order("FindElement", %{using: "css selector", value: selector}) do
      {:ok, %{error: nil, result: %{"value" => response}}} ->
        {:ok, Map.values(response)}

      {:ok, %{error: %{"error" => "no such element"}}} ->
        {:ok, []}

      error ->
        Logger.warning(fn -> "[Marionette.Browser] FindElement failed: #{inspect(error)}" end)
        {:error, :find_elements_failed}
    end
  end

  defp click(element_id) do
    case Connection.order("ElementClick", %{id: element_id}) do
      {:ok, %{error: %{"error" => "element not interactable"}}} ->
        :scrolling

      {:ok, %{error: nil}} ->
        :ok

      error ->
        Logger.warning(fn -> "[Marionette.Browser] Click failed: #{inspect(error)}" end)
        {:error, :click_failed}
    end
  end
end
