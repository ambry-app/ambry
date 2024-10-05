defmodule AmbryWeb.AuthorLive do
  @moduledoc """
  LiveView for showing an author and all of their authored books.
  """

  use AmbryWeb, :live_view

  alias Ambry.Books
  alias Ambry.People

  @per_page 36

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-8 p-4 sm:max-w-none sm:space-y-12 sm:p-10 md:max-w-screen-2xl md:p-12 lg:space-y-16 lg:p-16">
      <div class="flex items-center gap-4">
        <.link :if={@author.person.thumbnails} navigate={~p"/people/#{@author.person}"} class="flex-none">
          <img
            src={@author.person.thumbnails.extra_large}
            class="hidden rounded-full object-cover object-top shadow-lg sm:block sm:h-16 sm:w-16 xl:h-24 xl:w-24"
          />
        </.link>
        <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl xl:text-5xl">
          Written by
          <.link navigate={~p"/people/#{@author.person}"} class="hover:underline">
            <%= @author.name %>
          </.link>
        </h1>
      </div>

      <.book_tiles_stream id="books" stream={@streams.books} page={@page} end?={@end?} />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => author_id}, _session, socket) do
    author = People.get_author!(author_id)

    {:ok,
     socket
     |> assign(
       page_title: author.name,
       author: author,
       page: 1,
       empty?: false
     )
     |> paginate_books(1)}
  end

  @impl Phoenix.LiveView
  def handle_event("next-page", _, socket) do
    {:noreply, paginate_books(socket, socket.assigns.page + 1)}
  end

  def handle_event("prev-page", %{"_overran" => true}, socket) do
    {:noreply, paginate_books(socket, 1)}
  end

  def handle_event("prev-page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, paginate_books(socket, socket.assigns.page - 1)}
    else
      {:noreply, socket}
    end
  end

  defp paginate_books(socket, new_page) when new_page >= 1 do
    %{page: current_page, author: author} = socket.assigns

    {books, more?} =
      Books.get_authored_books(author, (new_page - 1) * @per_page, @per_page)

    {books, at, limit} =
      if new_page >= current_page do
        {books, -1, @per_page * 3 * -1}
      else
        {Enum.reverse(books), 0, @per_page * 3}
      end

    case books do
      [] ->
        assign(socket, end?: at == -1, empty?: new_page == 1)

      [_ | _] = books ->
        socket
        |> assign(end?: at == -1 && !more?, page: new_page)
        |> stream(:books, books, at: at, limit: limit)
    end
  end
end
