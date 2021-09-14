defmodule AmbryWeb.AuthorLive.Show do
  use AmbryWeb, :live_view

  alias Ambry.Authors
  alias AmbryWeb.Components.BookTiles

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl true
  def mount(%{"id" => author_id}, _session, socket) do
    author = Authors.get_author_with_books!(author_id)

    {:ok,
     socket
     |> assign(:page_title, author.name)
     |> assign(:author, author)}
  end
end
