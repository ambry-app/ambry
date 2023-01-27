defmodule AmbryWeb.SearchLive.Results do
  @moduledoc """
  LiveView for showing search results.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.SearchLive.Results.Components

  alias Ambry.Search

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-16 p-4 sm:max-w-none sm:space-y-24 sm:p-10 md:max-w-screen-2xl md:p-12 lg:space-y-32 lg:p-16">
      <.results :for={{type, items} <- @results} type={type} items={Enum.map(items, &elem(&1, 1))} />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"query" => query}, _session, socket) do
    query = String.trim(query)
    results = Search.search(query)

    {:ok,
     socket
     |> assign(:page_title, query)
     |> assign(:query, query)
     |> assign(:results, results)}
  end
end
