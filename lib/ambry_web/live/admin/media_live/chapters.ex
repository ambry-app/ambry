defmodule AmbryWeb.Admin.MediaLive.Chapters do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Media
  alias AmbryWeb.Admin.MediaLive.Chapters.AudibleImportForm
  alias AmbryWeb.Admin.MediaLive.Chapters.SourceImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _url, socket) do
    media = Media.get_media!(id)
    changeset = Media.change_media(media, %{}, for: :update)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(
       page_title: "#{media.book.title} - Chapters",
       media: media
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    changeset =
      socket.assigns.media
      |> Media.change_media(media_params, for: :update)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    case Media.update_media(socket.assigns.media, media_params, for: :update) do
      {:ok, media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated chapters for #{media.book.title}")
         |> push_navigate(to: ~p"/admin/media")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("import", %{"type" => import_type}, socket) do
    socket = assign(socket, import: %{type: String.to_existing_atom(import_type), query: socket.assigns.media.book.title})

    {:noreply, socket}
  end

  def handle_event("cancel-import", _params, socket) do
    {:noreply, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"media" => media_params}}, socket) do
    new_params = Map.merge(socket.assigns.form.params, media_params)
    changeset = Media.change_media(socket.assigns.media, new_params, for: :update)

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  # Forwards `handle_info` messages from `Task`s to live component
  def handle_info({_task_ref, {{:for, component, id}, payload}}, socket) do
    send_update(component, id: id, info: payload)
    {:noreply, socket}
  end

  def handle_info({:DOWN, _task_ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  defp import_form(:source), do: SourceImportForm
  defp import_form(:audible), do: AudibleImportForm

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
