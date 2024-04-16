defmodule AmbryWeb.Admin.AuditLive.Index do
  @moduledoc """
  LiveView for audit admin interface.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Media
  alias Ambry.Utils

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:header_title, "File Audit")
     |> assign(:page_title, "File Audit")}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _url, socket) do
    {:noreply, load_audit(socket)}
  end

  defp load_audit(socket) do
    audit = Media.orphaned_files_audit()

    deletable_files =
      Map.new(audit.orphaned_media_files, fn file ->
        {file.id, file.path}
      end)

    deletable_folders =
      Map.new(audit.orphaned_source_folders, fn folder ->
        {folder.id, folder.path}
      end)

    socket
    |> assign(:audit, audit)
    |> assign(:deletable_files, deletable_files)
    |> assign(:deletable_folders, deletable_folders)
  end

  @impl Phoenix.LiveView
  def handle_event("reload", _params, socket) do
    {:noreply, load_audit(socket)}
  end

  def handle_event("delete-file", %{"id" => file_id}, socket) do
    disk_path = Map.fetch!(socket.assigns.deletable_files, file_id)

    case Utils.try_delete_file(disk_path) do
      :ok ->
        {:noreply,
         socket
         |> load_audit()
         |> put_flash(:info, "File deleted.")}

      {:error, posix} ->
        {:noreply, put_flash(socket, :error, "Unable to delete file: #{posix}")}
    end
  end

  def handle_event("delete-folder", %{"id" => folder_id}, socket) do
    disk_path = Map.fetch!(socket.assigns.deletable_folders, folder_id)

    case Utils.try_delete_folder(disk_path) do
      :ok ->
        {:noreply,
         socket
         |> load_audit()
         |> put_flash(:info, "Folder deleted.")}

      {:error, posix, path} ->
        {:noreply, put_flash(socket, :error, "Unable to delete file/folder (#{posix}): #{path}")}
    end
  end

  def handle_event("row-click", %{"id" => media_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/media/#{media_id}/edit")}
  end

  defp format_filesize(size) do
    size |> FileSize.scale() |> FileSize.format()
  end

  defp no_problems(audit) do
    case audit do
      %{broken_media: [], orphaned_media_files: [], orphaned_source_folders: []} ->
        true

      _else ->
        false
    end
  end
end
