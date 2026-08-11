defmodule AmbryWeb.Admin.RecordingGroupLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Media
  alias Ambry.Media.RecordingGroup
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, media_options: Media.media_for_select())}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    group = Media.get_recording_group!(id)
    changeset = Media.change_recording_group_form(group)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: group.name,
      group: group
    )
  end

  defp apply_action(socket, :new, _params) do
    group = %RecordingGroup{media: []}
    changeset = Media.change_recording_group_form(group)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Group",
      group: group
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"recording_group_form" => group_params}, socket) do
    changeset =
      socket.assigns.group
      |> Media.change_recording_group_form(group_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"recording_group_form" => group_params}, socket) do
    save_group(socket, socket.assigns.live_action, group_params)
  end

  defp save_group(socket, :edit, group_params) do
    case Media.update_recording_group_from_form(socket.assigns.group, group_params) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{group.name}")
         |> push_navigate(to: ~p"/admin/groups")}

      {:error, error} ->
        {:noreply, handle_save_error(socket, error)}
    end
  end

  defp save_group(socket, :new, group_params) do
    case Media.create_recording_group_from_form(group_params) do
      {:ok, group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{group.name}")
         |> push_navigate(to: ~p"/admin/groups")}

      {:error, error} ->
        {:noreply, handle_save_error(socket, error)}
    end
  end

  # A member write can fail with the MEDIA's changeset, which this form has
  # no inputs for — say so rather than exploding the form over it.
  defp handle_save_error(socket, %Changeset{data: %Media.RecordingGroupForm{}} = changeset) do
    assign_form(socket, changeset)
  end

  defp handle_save_error(socket, _other) do
    put_flash(socket, :error, "Couldn't save one of the recordings' membership.")
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
