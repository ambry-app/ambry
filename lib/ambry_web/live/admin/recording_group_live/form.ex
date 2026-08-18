defmodule AmbryWeb.Admin.RecordingGroupLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Books
  alias Ambry.Media
  alias Ambry.Media.RecordingGroup
  alias AmbryWeb.Admin.ReturnTo
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    # The list the operator came from, kept so every way out of this form goes
    # back to it. See `AmbryWeb.Admin.ReturnTo`.
    {:ok, assign(socket, list_params: ReturnTo.list_params(params))}
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
      # the composed display: the name is local to the book
      page_title: "#{group.name} (#{group.book.title})",
      group: group,
      book_id: group.book_id
    )
  end

  defp apply_action(socket, :new, _params) do
    group = %RecordingGroup{media: []}
    changeset = Media.change_recording_group_form(group)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Set",
      group: group,
      book_id: nil
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"recording_group_form" => group_params}, socket) do
    changeset =
      socket.assigns.group
      |> Media.change_recording_group_form(group_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign_form(changeset)
     # The member picker searches within the chosen book — a set can only hold
     # its own book's recordings. On the edit page with members the book
     # renders as static text and posts nothing, so this falls back to the
     # group's own book.
     |> assign(book_id: group_params["book_id"] || socket.assigns.group.book_id)}
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
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/sets", socket.assigns.list_params, group.id)
         )}

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
         |> push_navigate(
           to: ReturnTo.path(~p"/admin/sets", socket.assigns.list_params, group.id)
         )}

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
    put_flash(socket, :error, "Couldn't save one of the audiobooks' membership.")
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
