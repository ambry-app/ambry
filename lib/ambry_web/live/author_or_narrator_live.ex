defmodule AmbryWeb.AuthorOrNarratorLive do
  @moduledoc """
  LiveView for showing an author (or narrator) and all of their authored (or
  narrated) books.
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
        <.link
          :if={@author_or_narrator.person.image_path}
          navigate={~p"/people/#{@author_or_narrator.person}"}
          class="flex-none"
        >
          <img
            src={@author_or_narrator.person.image_path}
            class="hidden rounded-full object-cover object-top shadow-lg sm:block sm:h-16 sm:w-16 xl:h-24 xl:w-24"
          />
        </.link>
        <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl xl:text-5xl">
          <%= header_text(@live_action) %>
          <.link navigate={~p"/people/#{@author_or_narrator.person}"} class="hover:underline">
            <%= @author_or_narrator.name %>
          </.link>
        </h1>
      </div>

      <.book_tiles_stream id="books" stream={@streams.books} page={@page} end?={@end?} />
    </div>
    """
  end

  defp header_text(:author), do: "Written by"
  defp header_text(:narrator), do: "Narrated by"

  @impl Phoenix.LiveView
  def mount(%{"id" => author_or_narrator_id}, _session, socket) do
    author_or_narrator =
      case socket.assigns.live_action do
        :author -> People.get_author!(author_or_narrator_id)
        :narrator -> People.get_narrator!(author_or_narrator_id)
      end

    {:ok,
     socket
     |> assign(
       page_title: author_or_narrator.name,
       author_or_narrator: author_or_narrator,
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
    %{page: current_page, author_or_narrator: author_or_narrator} = socket.assigns

    {books, more?} =
      Books.get_authored_books(author_or_narrator, (new_page - 1) * @per_page, @per_page)

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
