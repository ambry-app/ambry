defmodule AmbryWeb.LibraryLive do
  @moduledoc """
  LiveView for the library page.
  """

  use AmbryWeb, :live_view

  alias Ambry.Media

  @per_page 36

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md p-4 sm:max-w-none sm:p-10 md:max-w-screen-2xl md:p-12 lg:p-16">
      <%= if @empty? do %>
        <div class="mt-10">
          <FA.icon name="book-open" class="mx-auto h-24 w-24 fill-current" />

          <p class="mt-4 text-center">
            The library is empty!
            <%= if @current_user.admin do %>
              Head on over to the
              <.brand_link navigate={~p"/admin/books/new"}>
                admin books
              </.brand_link>
              page to add your first book.
            <% end %>
          </p>
        </div>
      <% else %>
        <.media_tiles_stream id="media" stream={@streams.media} page={@page} end?={@end?} />
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Library", page: 1, empty?: false)
     |> paginate_media(1)}
  end

  @impl Phoenix.LiveView
  def handle_event("next-page", _, socket) do
    {:noreply, paginate_media(socket, socket.assigns.page + 1)}
  end

  def handle_event("prev-page", %{"_overran" => true}, socket) do
    {:noreply, paginate_media(socket, 1)}
  end

  def handle_event("prev-page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, paginate_media(socket, socket.assigns.page - 1)}
    else
      {:noreply, socket}
    end
  end

  defp paginate_media(socket, new_page) when new_page >= 1 do
    %{page: current_page} = socket.assigns
    {media, more?} = Media.get_recent_media((new_page - 1) * @per_page, @per_page)

    {media, at, limit} =
      if new_page >= current_page do
        {media, -1, @per_page * 3 * -1}
      else
        {Enum.reverse(media), 0, @per_page * 3}
      end

    case media do
      [] ->
        assign(socket, end?: at == -1, empty?: new_page == 1)

      [_ | _] = media ->
        socket
        |> assign(end?: at == -1 && !more?, page: new_page)
        |> stream(:media, media, at: at, limit: limit)
    end
  end
end
