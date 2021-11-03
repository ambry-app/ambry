defmodule AmbryWeb.HeaderLive.Bookmarks do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias Ambry.Media

  alias Surface.Components.Form
  alias Surface.Components.Form.{Field, TextInput}

  # alias AmbryWeb.Components.ChevronUp
  # alias Surface.Components.LiveRedirect

  # prop player_state, :any, required: true
  # prop playing, :boolean, required: true
  # prop click, :event, required: true
  prop dismiss, :event, required: true
  prop media_id, :integer, required: true
  prop user_id, :integer, required: true

  data bookmarks, :list, default: []
  data editing, :any
  # data show_bookmarks, :boolean, default: false

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:editing, nil)
     |> load_bookmarks()}
  end

  defp load_bookmarks(socket) do
    %{media_id: media_id, user_id: user_id} = socket.assigns

    assign(socket, :bookmarks, Media.list_bookmarks(user_id, media_id))
  end

  @impl Phoenix.LiveComponent
  def handle_event("add-bookmark", %{"position" => position_string}, socket) do
    %{media_id: media_id, user_id: user_id} = socket.assigns

    {:ok, bookmark} =
      Media.create_bookmark(%{
        media_id: media_id,
        user_id: user_id,
        position: position_string
      })

    {:noreply,
     socket
     |> load_bookmarks()
     |> edit_bookmark(bookmark)}
  end

  def handle_event("edit-bookmark", %{"id" => bookmark_id}, socket) do
    bookmark = Media.get_bookmark!(bookmark_id)

    {:noreply, edit_bookmark(socket, bookmark)}
  end

  def handle_event("update-bookmark", %{"bookmark" => params}, socket) do
    bookmark = Media.get_bookmark!(socket.assigns.editing.id)
    {:ok, _bookmark} = Media.update_bookmark(bookmark, params)

    {:noreply,
     socket
     |> assign(:editing, nil)
     |> load_bookmarks()}
  end

  def handle_event("delete-bookmark", %{"id" => bookmark_id}, socket) do
    bookmark = Media.get_bookmark!(bookmark_id)
    {:ok, _bookmark} = Media.delete_bookmark(bookmark)

    {:noreply, load_bookmarks(socket)}
  end

  defp edit_bookmark(socket, bookmark) do
    changeset = Media.change_bookmark(bookmark, %{})

    assign(socket, :editing, %{id: bookmark.id, changeset: changeset})
  end
end
