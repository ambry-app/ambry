defmodule AmbryWeb.SearchLive do
  @moduledoc """
  LiveView for showing search results.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.SearchLive.Components

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Media.Editions
  alias Ambry.Search

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-16 p-4 sm:max-w-none sm:space-y-24 sm:p-10 md:max-w-screen-2xl md:p-12 lg:space-y-32 lg:p-16">
      <section>
        <.section_header>
          Results for "{@query}"
        </.section_header>

        <.grid>
          <.result_tile :for={result <- @results} result={result} />
        </.grid>
      </section>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"query" => query}, _session, socket) do
    query = String.trim(query)

    # tile system v2: books with no ready editions are hidden from users,
    # and a series is hidden when none of its books are visible
    results = query |> Search.search() |> Enum.filter(&visible?/1)

    {:ok,
     socket
     |> assign(:page_title, query)
     |> assign(:query, query)
     |> assign(:results, results)}
  end

  defp visible?(%Book{} = book), do: Editions.from_media(book.media) != []

  defp visible?(%Series{} = series), do: Enum.any?(series.series_books, &visible?(&1.book))

  defp visible?(_person), do: true
end
