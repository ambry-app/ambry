defmodule AmbryWeb.Components.SearchBox do
  @moduledoc false

  use AmbryWeb, :live_component

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={["absolute top-4 w-full sm:left-1/2 sm:max-w-md sm:-translate-x-1/2 md:max-w-xl lg:max-w-3xl", if(!@is_open, do: "hidden")]}
      phx-click-away={@hide_search}
      phx-window-keydown={@hide_search}
      phx-key="escape"
      phx-hook="search-box"
    >
      <div class="mx-4 flex rounded-sm border border-zinc-200 bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 sm:mx-0">
        <span phx-click={@hide_search} title="Back" class="ml-4 flex-none cursor-pointer self-center">
          <FA.icon name="arrow-left" class="h-5 w-5 fill-zinc-500" />
        </span>
        <.form :let={form} for={%{"query" => @query}} as={:search} phx-submit="search" phx-target={@myself} class="grow">
          <input
            type="search"
            id="search-input"
            value={form[:query].value}
            name={form[:query].name}
            placeholder="Search"
            class="w-full border-0 bg-transparent placeholder:font-bold placeholder:text-zinc-500 focus:border-0 focus:outline-none focus:ring-0"
            phx-autofocus={@is_open}
          />
        </.form>
        <span
          id="clear-search"
          title="Clear"
          class={["mr-4 flex-none cursor-pointer self-center", if(!@is_open, do: "hidden")]}
        >
          <FA.icon name="xmark" class="h-5 w-5 fill-zinc-500" />
        </span>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    case String.trim(query) do
      "" -> {:noreply, socket}
      query -> {:noreply, push_navigate(socket, to: ~p"/search/#{query}")}
    end
  end
end
