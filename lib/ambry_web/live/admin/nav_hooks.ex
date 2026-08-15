defmodule AmbryWeb.Admin.NavHooks do
  @moduledoc """
  LiveView lifecycle hooks to help render the admin nav.

  The nav carries the one number that is true no matter which page the
  operator is on: how much is waiting in the inbox. It lives here rather than
  on the overview because that was the whole argument for landing on the
  inbox instead of a dashboard — saving a click — and a badge saves it from
  everywhere, including from inside the form the operator is already in.

  Only the inbox gets one. A count on every nav item is a nav bar nobody
  reads; this one is a queue with work in it, and the rest are lists.

  Recomputed on `handle_params`, which is every navigation. It is a single
  grouped count, and the inbox page keeps its own live numbers — the badge is
  a "there is work over there" signal, not a live readout. Nothing here
  polls: the one thing on an admin page that has to stay live without the
  operator moving is the background-work indicator, and that is
  `AmbryWeb.Admin.JobIndicatorLive`, which owns its own process precisely so
  this hook doesn't have to drag every page through a re-render.
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
