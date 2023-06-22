defmodule GoodReads.Browser do
  @moduledoc """
  Headless browser interface of scraping GoodReads.

  This serializes all access to the Marionette.Socket so that simultaneous
  requests can't interfere with each other.
  """

  # TODO: this thing needs to be less brittle and possibly not GoodReads specific

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

  def get_page_html(path, actions \\ []) do
    GenServer.call(__MODULE__, {:get_page_html, path, actions}, @timeout)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:get_page_html, path, actions}, _from, state) do
    url = "#{@url}#{path}"
    Logger.debug(fn -> "[GoodReads.Browser] requesting #{url}" end)

    response =
      case Marionette.Socket.order("Navigate", %{url: url}) do
        %{error: nil} ->
          process_page(actions)

        %{error: error} ->
          {:error, inspect(error)}
      end

    {:reply, response, state}
  end

  defp process_page(actions) do
    # FIXME: rewrite `get_fully_loaded_page_source` to instead use a
    # `{:wait_for_no, selector}` action instead of getting and parsing the
    # entire page source every time.
    with {:ok, _html} <- get_fully_loaded_page_source(),
         :ok <- maybe_close_login_popup(),
         :ok <- perform_actions(actions) do
      get_fully_loaded_page_source()
    end
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

  defp maybe_close_login_popup do
    case Marionette.Socket.order("FindElement", %{
           using: "css selector",
           value: "button[aria-label='Close']"
         }) do
      %{error: nil, result: %{"value" => response}} ->
        [element_id] = Map.values(response)
        try_click(element_id)

      _else ->
        :ok
    end
  end

  defp try_click(element_id, attempt \\ 0)
  defp try_click(_element_id, @max_attempts), do: {:error, :click_failed}

  defp try_click(element_id, attempt) do
    case Marionette.Socket.order("ElementClick", %{id: element_id}) do
      %{error: %{"error" => "element not interactable"}} ->
        Process.sleep(@sleep_interval)
        try_click(element_id, attempt + 1)

      %{error: nil} ->
        :ok
    end
  end

  defp perform_actions([]), do: :ok

  defp perform_actions([{:click, selector} | rest]) do
    %{error: nil, result: %{"value" => response}} =
      Marionette.Socket.order("FindElement", %{using: "css selector", value: selector})

    [element_id] = Map.values(response)

    :ok = try_click(element_id)

    perform_actions(rest)
  end

  defp perform_actions([{:wait_for, _selector} | rest]) do
    # TODO:
    perform_actions(rest)
  end
end

# when no element is found:
# %Marionette.Wire.Response{
#   message_id: 4195576971,
#   error: %{
#     "error" => "no such element",
#     "message" => "Unable to locate element: button[aria-label='Close']",
#     "stacktrace" => "RemoteError@chrome://remote/content/shared/RemoteError.sys.mjs:8:8\nWebDriverError@chrome://remote/content/shared/webdriver/Errors.sys.mjs:183:5\nNoSuchElementError@chrome://remote/content/shared/webdriver/Errors.sys.mjs:395:5\nelement.find/</<@chrome://remote/content/marionette/element.sys.mjs:134:16\n"
#   },
#   result: nil
# }
