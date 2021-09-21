defmodule AmbryWeb.BookLive.Show do
  use AmbryWeb, :live_view

  alias Ambry.Books
  alias AmbryWeb.BookLive.{Header, PlayButton}

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl true
  def mount(%{"id" => book_id}, _session, socket) do
    book = Books.get_book_with_media!(book_id)

    {:ok,
     socket
     |> assign(:page_title, book.title)
     |> assign(:book, book)}
  end

  def recording_type(%{abridged: true}), do: "Abridged"
  def recording_type(%{abridged: false}), do: "Unabridged"
end
