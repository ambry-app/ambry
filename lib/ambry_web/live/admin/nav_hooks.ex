defmodule AmbryWeb.Admin.NavHooks do
  @moduledoc """
  LiveView lifecycle hooks to help render the admin nav.

  The one number that's true from anywhere is how much is waiting in the
  inbox, so that's the only nav item with a badge. Recomputed on
  `handle_params`, which is every navigation: it's a "there is work over
  there" signal, not a live readout. The live one is
  `AmbryWeb.Admin.JobIndicatorLive`, which owns its own process.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Ambry.Inbox

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :set_admin_nav_active_path, :handle_params, fn
       _params, url, socket ->
         {:cont,
          assign(socket,
            admin_nav_active_path: URI.parse(url).path,
            admin_inbox_pending: Inbox.count_by_status() |> Map.get(:pending, 0)
          )}
     end)}
  end
end
