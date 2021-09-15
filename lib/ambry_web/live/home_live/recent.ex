defmodule AmbryWeb.HomeLive.Recent do
  use AmbryWeb, :live_view

  alias Ambry.Books
  alias AmbryWeb.Components.BookTiles

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl true
  def mount(_params, _session, socket) do
    books = Books.get_recent_books!()

    {:ok,
     socket
     |> assign(:books, books)}
  end
end
