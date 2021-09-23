defmodule AmbryWeb.HomeLive.RecentBooks do
  use AmbryWeb, :live_component

  alias Ambry.Books
  alias AmbryWeb.Components.BookTiles

  @limit 10

  data show_load_more?, :boolean, default: true
  data books, :list, default: []

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> load_books()}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply, load_books(socket)}
  end

  defp load_books(%{assigns: assigns} = socket) do
    books = Map.get(assigns, :books, [])
    offset = Map.get(assigns, :offset, 0)
    more_books = Books.get_recent_books!(offset, @limit)
    books = books ++ more_books
    show_load_more? = length(more_books) == @limit

    socket
    |> assign(:books, books)
    |> assign(:offset, offset + @limit)
    |> assign(:show_load_more?, show_load_more?)
  end
end
