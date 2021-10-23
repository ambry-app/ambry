defmodule AmbryWeb.Admin.AuditLive.Index do
  @moduledoc """
  LiveView for audit admin interface.
  """

  use AmbryWeb, :live_view

  alias Ambry.Media

  alias AmbryWeb.Admin.Components.AdminNav

  alias Surface.Components.LiveRedirect

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}
  on_mount {AmbryWeb.Admin.Auth, :ensure_mounted_admin_user}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Auditing Media")}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _url, socket) do
    {:noreply, load_audit(socket)}
  end

  defp load_audit(socket) do
    audit = Media.orphaned_files_audit()

    assign(socket, :audit, audit)
  end

  @impl Phoenix.LiveView
  def handle_event("reload", _params, socket) do
    {:noreply, load_audit(socket)}
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
