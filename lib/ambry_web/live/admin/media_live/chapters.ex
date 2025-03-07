defmodule AmbryWeb.Admin.MediaLive.Chapters do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Media
  alias AmbryWeb.Admin.MediaLive.Chapters.AudibleImportForm
  alias AmbryWeb.Admin.MediaLive.Chapters.SourceImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    media = Media.get_media!(id)
    changeset = Media.change_media(media, %{})

    {:ok,
     socket
     |> assign_form(changeset)
     |> assign(
       page_title: "#{media.book.title} - Chapters",
       media: media,
       import: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"import" => type}, _url, socket) do
    query = socket.assigns.media.book.title
    import_type = String.to_existing_atom(type)
    {:noreply, assign(socket, import: %{type: import_type, query: query})}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    changeset =
      socket.assigns.media
      |> Media.change_media(media_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    case Media.update_media(socket.assigns.media, media_params) do
      {:ok, media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated chapters for #{media.book.title}")
         |> push_navigate(to: ~p"/admin/media")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("open-import-form", %{"type" => type}, socket) do
    query = socket.assigns.media.book.title
    import_type = String.to_existing_atom(type)
    socket = assign(socket, import: %{type: import_type, query: query})

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"media" => media_params}}, socket) do
    new_params = Map.merge(socket.assigns.form.params, media_params)
    changeset = Media.change_media(socket.assigns.media, new_params)

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp import_form(:source), do: SourceImportForm
  defp import_form(:audible), do: AudibleImportForm

  defp open_import_form(media, type),
    do: JS.patch(~p"/admin/media/#{media}/chapters?import=#{type}")

  defp close_import_form(media), do: JS.patch(~p"/admin/media/#{media}/chapters", replace: true)
end
