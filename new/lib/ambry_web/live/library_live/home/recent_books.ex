defmodule AmbryWeb.LibraryLive.Home.RecentBooks do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Ambry.Books

  @limit 25

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="recent-books">
      <%= if @books != [] do %>
        <div class="">
          <.section_header>Newest books</.section_header>

          <.book_tiles
            books={@books}
            show_load_more={@show_load_more?}
            current_page={@current_page}
            infinite_scroll_target="#recent-books"
          />
        </div>
      <% else %>
        <div class="mt-10">
          <FA.icon name="book-open" class="mx-auto h-24 w-24 fill-current" />

          <p class="mt-4 text-center">
            The library is empty!
            <%= if @show_admin_links? do %>
              Head on over to the
              <.brand_link navigate={~p"/admin/books/new"}>
                admin books
              </.brand_link>
              page to add your first book.
            <% end %>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> load_books()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("load-more", _params, socket) do
    {:noreply, load_books(socket)}
  end

  defp load_books(%{assigns: assigns} = socket) do
    current_page = Map.get(assigns, :current_page, 0)
    books = Map.get(assigns, :books, [])
    offset = Map.get(assigns, :offset, 0)
    {more_books, has_more?} = Books.get_recent_books(offset, @limit)
    books = books ++ more_books

    socket
    |> assign(:current_page, current_page + 1)
    |> assign(:books, books)
    |> assign(:offset, offset + @limit)
    |> assign(:show_load_more?, has_more?)
  end
end
