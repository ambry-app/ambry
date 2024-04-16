defmodule AmbryWeb.SeriesLive do
  @moduledoc """
  LiveView for showing all books in a series.
  """

  use AmbryWeb, :live_view

  alias Ambry.Books

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-10 p-4 sm:max-w-none sm:space-y-14 sm:p-10 md:max-w-screen-2xl md:p-12 lg:space-y-18 lg:p-16">
      <div class="space-y-1">
        <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl xl:text-5xl">
          <%= @series.name %>
        </h1>

        <p class="text-xl text-zinc-800 dark:text-zinc-200">
          by <.people_links people={@authors} />
        </p>
      </div>

      <.book_tiles books={@series.series_books} />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => series_id}, _session, socket) do
    series = Books.get_series_with_books!(series_id)

    authors =
      series.series_books
      |> Enum.flat_map(& &1.book.authors)
      |> Enum.uniq()

    {:ok,
     socket
     |> assign(:page_title, series.name)
     |> assign(:series, series)
     |> assign(:authors, authors)}
  end
end
