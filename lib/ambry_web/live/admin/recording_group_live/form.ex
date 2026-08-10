defmodule AmbryWeb.Admin.RecordingGroupLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Media
  alias Ambry.Media.RecordingGroup
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    group = Media.get_recording_group!(id)
    changeset = Media.change_recording_group(group)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: group.name,
      group: group
    )
  end

  defp apply_action(socket, :new, _params) do
    group = %RecordingGroup{media: []}
    changeset = Media.change_recording_group(group)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Group",
      group: group
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"recording_group" => group_params}, socket) do
    changeset =
      socket.assigns.group
      |> Media.change_recording_group(group_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"recording_group" => group_params}, socket) do
    save_group(socket, socket.assigns.live_action, group_params)
  end

  defp save_group(socket, :edit, group_params) do
    case Media.update_recording_group(socket.assigns.group, group_params) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{group.name}")
         |> push_navigate(to: ~p"/admin/groups")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_group(socket, :new, group_params) do
    case Media.create_recording_group(group_params) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{group.name}")
         |> push_navigate(to: ~p"/admin/groups")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  # Members come from the group preload, so their own recording_group assoc
  # is unloaded — the part label needs the group passed explicitly.
  defp member_label(media, group) do
    title = media.title || media.book.title

    case Ambry.Media.Media.part_label(media, group) do
      nil -> title
      label -> "#{label} — #{title}"
    end
  end
end
