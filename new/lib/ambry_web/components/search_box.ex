defmodule AmbryWeb.Components.SearchBox do
  @moduledoc false

  use AmbryWeb, :live_component

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="hidden absolute top-4 w-full sm:max-w-md md:max-w-xl lg:max-w-3xl sm:left-1/2 sm:-translate-x-1/2"
      phx-click-away={hide_search()}
      phx-window-keydown={hide_search()}
      phx-key="escape"
    >
      <div class="mx-4 flex rounded-sm border border-zinc-200 bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 sm:mx-0">
        <span phx-click={hide_search()} title="Back" class="ml-4 flex-none cursor-pointer self-center">
          <FA.icon name="arrow-left" class="h-5 w-5 fill-zinc-500" />
        </span>
        <.form :let={f} for={:search} phx-submit="search" phx-target={@myself} class="flex-grow">
          <%= Phoenix.HTML.Form.search_input(f, :query,
            id: "search-input",
            placeholder: "Search",
            class: "w-full border-0 bg-transparent placeholder:font-bold placeholder:text-zinc-500 focus:border-0 focus:outline-none focus:ring-0",
            onfocus: on_focus_input(),
            oninput: on_input()
          ) %>
        </.form>
        <span
          id="clear-search"
          title="Clear"
          class="mr-4 hidden flex-none cursor-pointer self-center"
          onclick={on_clear_click()}
        >
          <FA.icon name="xmark" class="h-5 w-5 fill-zinc-500" />
        </span>
      </div>
    </div>
    """
  end

  defp on_focus_input do
    """
    const clearButton = document.getElementById('clear-search');
    this.value = '';
    clearButton.classList.add('hidden');
    """
  end

  defp on_input do
    """
    const clearButton = document.getElementById('clear-search');
    this.value == ''
      ? clearButton.classList.add('hidden')
      : clearButton.classList.remove('hidden');
    """
  end

  defp on_clear_click do
    """
    const searchInput = document.getElementById('search-input');
    searchInput.value = '';
    searchInput.focus();
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    case String.trim(query) do
      "" -> {:noreply, socket}
      query -> {:noreply, push_redirect(socket, to: ~p"/search/#{query}")}
    end
  end
end
