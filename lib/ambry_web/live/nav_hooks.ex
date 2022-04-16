defmodule AmbryWeb.NavHooks do
  @moduledoc """
  LiveView lifecycle hooks to help render the nav.
  """

  import Phoenix.LiveView

  def on_mount(:default, params, _session, socket) do
    case params do
      :not_mounted_at_router ->
        {:cont, socket}

      _params ->
        {:cont,
         attach_hook(socket, :set_nav_active_path, :handle_params, fn
           _params, url, socket ->
             {:cont, assign(socket, nav_active_path: URI.parse(url).path)}
         end)}
    end
  end
end
