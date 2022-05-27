defmodule AmbryWeb.NowPlayingLive.Index.Bookmarks do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.TimeUtils

  alias Ambry.Media

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_bookmark, nil)
     |> get_bookmarks()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("add-bookmark", %{"time" => time}, socket) do
    %{media: media, user: user} = socket.assigns

    params = %{
      position: time,
      media_id: media.id,
      user_id: user.id
    }

    {:ok, _bookmark} = Media.create_bookmark(params)

    {:noreply, get_bookmarks(socket)}
  end

  def handle_event("edit-bookmark", %{"id" => id}, socket) do
    bookmark = Media.get_bookmark!(id)
    changeset = Media.change_bookmark(bookmark)

    {:noreply, assign(socket, %{selected_bookmark: bookmark, changeset: changeset})}
  end

  def handle_event("cancel-edit-bookmark", _params, socket) do
    {:noreply, assign(socket, %{selected_bookmark: nil, changeset: nil})}
  end

  def handle_event("save-bookmark", %{"bookmark" => params}, socket) do
    {:ok, _bookmark} = Media.update_bookmark(socket.assigns.selected_bookmark, params)

    {:noreply,
     socket
     |> get_bookmarks()
     |> assign(%{selected_bookmark: nil, changeset: nil})}
  end

  def handle_event("delete-bookmark", _params, socket) do
    {:ok, _bookmark} = Media.delete_bookmark(socket.assigns.selected_bookmark)

    {:noreply,
     socket
     |> get_bookmarks()
     |> assign(%{selected_bookmark: nil, changeset: nil})}
  end

  defp get_bookmarks(socket) do
    %{media: media, user: user} = socket.assigns

    assign(socket, :bookmarks, Media.list_bookmarks(user.id, media.id))
  end
end
