defmodule AmbryWeb.NarratorLive do
  @moduledoc """
  LiveView for showing a narrator and all of their narrated audiobooks.
  """

  use AmbryWeb, :live_view

  alias Ambry.Media
  alias Ambry.People

  @per_page 36

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-8 p-4 sm:max-w-none sm:space-y-12 sm:p-10 md:max-w-screen-2xl md:p-12 lg:space-y-16 lg:p-16">
      <div class="flex items-center gap-4">
        <.link :if={@narrator.person.thumbnails} navigate={~p"/people/#{@narrator.person}"} class="flex-none">
          <img
            src={@narrator.person.thumbnails.extra_large}
            class="hidden rounded-full object-cover object-top shadow-lg sm:block sm:h-16 sm:w-16 xl:h-24 xl:w-24"
          />
        </.link>
        <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl xl:text-5xl">
          Narrated by
          <.link navigate={~p"/people/#{@narrator.person}"} class="hover:underline">
            <%= @narrator.name %>
          </.link>
        </h1>
      </div>

      <.media_tiles_stream id="media" stream={@streams.media} page={@page} end?={@end?} />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => narrator_id}, _session, socket) do
    narrator = People.get_narrator!(narrator_id)

    {:ok,
     socket
     |> assign(
       page_title: narrator.name,
       narrator: narrator,
       page: 1,
       empty?: false
     )
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
    %{page: current_page, narrator: narrator} = socket.assigns

    {media, more?} =
      Media.get_narrated_media(narrator, (new_page - 1) * @per_page, @per_page)

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
