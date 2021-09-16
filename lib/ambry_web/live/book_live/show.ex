defmodule AmbryWeb.BookLive.Show do
  use AmbryWeb, :live_view

  alias Ambry.Books
  alias Ambry.Media
  alias AmbryWeb.BookLive.Header

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl true
  def mount(%{"id" => book_id}, _session, socket) do
    book = Books.get_book_with_media!(book_id)

    {:ok,
     socket
     |> assign(:page_title, book.title)
     |> assign(:book, book)}
  end

  @impl true
  def handle_event("load-media", %{"media_id" => media_id}, socket) do
    user = socket.assigns.current_user

    Media.load_media!(user.id, media_id)

    {:noreply, socket}
  end

  def recording_type(%{abridged: true}), do: "Abridged"
  def recording_type(%{abridged: false}), do: "Unabridged"
end
