defmodule AmbryWeb.NowPlayingLive.Index.Bookmarks do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.TimeUtils

  alias Ambry.Media

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex">
        <div class="flex-grow" />
        <span
          class="text-brand flex cursor-pointer items-center pt-4 font-bold hover:underline dark:text-brand-dark"
          phx-click="add-bookmark"
          phx-target={@myself}
          x-bind:phx-value-time="$store.player.progress.actual"
        >
          New <FA.icon name="plus" class="ml-2 h-4 w-4 fill-current" />
        </span>
      </div>

      <%= if @bookmarks == [] do %>
        <p class="p-4 text-center font-semibold text-zinc-800 dark:text-zinc-200">
          You have no bookmarks.
        </p>
      <% else %>
        <table class="w-full">
          <%= for bookmark <- @bookmarks do %>
            <%= if @selected_bookmark && @selected_bookmark.id == bookmark.id do %>
              <tr>
                <td class="border-b border-zinc-100 py-2 pl-4 dark:border-zinc-900">
                  <.form :let={f} for={@changeset} phx-submit="save-bookmark" phx-target={@myself}>
                    <div class="flex items-center space-x-2">
                      <button
                        type="button"
                        class="flex-none text-zinc-500 hover:text-zinc-50"
                        phx-click="cancel-edit-bookmark"
                        phx-target={@myself}
                      >
                        <FA.icon name="xmark" class="h-5 w-5 fill-current" />
                      </button>
                      <%!-- <.text_input form={f} field={:label} placeholder="Label" /> --%>
                      <button type="sutmit" class="text-zinc-500 hover:text-brand-dark">
                        <FA.icon name="check" class="h-5 w-5 fill-current" />
                      </button>
                      <button
                        type="button"
                        phx-click="delete-bookmark"
                        phx-target={@myself}
                        class="text-zinc-500 hover:text-red-500"
                      >
                        <FA.icon name="trash" class="h-5 w-5 fill-current" />
                      </button>
                    </div>
                  </.form>
                </td>

                <td class="border-b border-zinc-100 py-4 pr-4 text-right tabular-nums dark:border-zinc-900">
                  <%= format_timecode(bookmark.position) %>
                </td>
              </tr>
            <% else %>
              <tr class="group cursor-pointer" x-on:click={"mediaPlayer.seek(#{bookmark.position})"}>
                <td class="border-b border-zinc-100 py-4 pl-4 dark:border-zinc-900">
                  <div class="flex items-center space-x-2">
                    <div
                      id={"bookmark-#{bookmark.id}"}
                      class="invisible flex-none text-zinc-500 hover:text-brand-dark group-hover:visible"
                      phx-hook="captureClick"
                      phx-target={@myself}
                      phx-event="edit-bookmark"
                      phx-value-id={bookmark.id}
                    >
                      <FA.icon name="pencil" class="h-4 w-4 fill-current" />
                    </div>
                    <p>
                      <%= if bookmark.label do %>
                        <%= bookmark.label %>
                      <% else %>
                        (unlabeled)
                      <% end %>
                    </p>
                  </div>
                </td>

                <td class="border-b border-zinc-100 py-4 pr-4 text-right tabular-nums dark:border-zinc-900">
                  <%= format_timecode(bookmark.position) %>
                </td>
              </tr>
            <% end %>
          <% end %>
        </table>
      <% end %>
    </div>
    """
  end

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
