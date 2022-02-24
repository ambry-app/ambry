defmodule AmbryWeb.Components.SearchBox do
  @moduledoc false

  use AmbryWeb, :p_live_component

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    case String.trim(query) do
      "" ->
        {:noreply, socket}

      query ->
        {:noreply, push_redirect(socket, to: Routes.search_results_path(socket, :results, query))}
    end
  end
end
