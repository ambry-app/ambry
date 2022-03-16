defmodule AmbryWeb.Admin.NavHooks do
  @moduledoc """
  LiveView lifecycle hooks to help render the admin nav.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :set_admin_nav_active_path, :handle_params, fn
       _params, url, socket ->
         {:cont, assign(socket, admin_nav_active_path: URI.parse(url).path)}
     end)}
  end
end
