defmodule AmbryWeb.Admin.NavHooks do
  @moduledoc """
  The ambient state every admin page carries, regardless of what it is about.

  Two things belong to the chrome rather than to any page: how much is waiting
  in the inbox, and what the background queues are doing. Both are true no
  matter which form the operator has open, and both are the reason they would
  otherwise have to go somewhere else to look.

  ## Why it polls, and why here

  Oban does not broadcast "started executing", so the only way to know the
  server is busy is to ask. Asking from a hook rather than from each LiveView
  means it happens once, on every admin surface, including the long forms
  where an operator sits while a job they started runs.

  Two rates: quick while something is in flight, slow when nothing is. The
  slow rate is deliberately slower than the overview's own — the overview is
  a page you are *watching*, the header is a thing you glance at, and this
  tick re-renders whatever page is open, including the import form.

  ## The message must be swallowed

  Most admin LiveViews have no `handle_info/2` at all, and several match only
  on structs. An un-halted tick would crash them, so the hook halts on its own
  message and passes everything else through untouched.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Ambry.Inbox
  alias Ambry.Jobs

  @busy_tick 5_000
  @idle_tick 60_000

  def on_mount(:default, _params, _session, socket) do
    socket = socket |> load() |> schedule_tick()

    {:cont,
     socket
     |> attach_hook(:set_admin_nav_active_path, :handle_params, fn _params, url, socket ->
       {:cont, socket |> assign(admin_nav_active_path: URI.parse(url).path) |> load()}
     end)
     |> attach_hook(:refresh_admin_ambient, :handle_info, fn
       :refresh_admin_ambient, socket -> {:halt, socket |> load() |> schedule_tick()}
       _other_message, socket -> {:cont, socket}
     end)}
  end

  defp load(socket) do
    assign(socket,
      admin_jobs: Jobs.summary(),
      admin_inbox_pending: Inbox.count_by_status() |> Map.get(:pending, 0)
    )
  end

  # One timer, re-armed by its own firing. Not scheduled on the dead render:
  # that process is thrown away, and a timer in it is a message nobody reads.
  defp schedule_tick(socket) do
    if connected?(socket) do
      delay = if Jobs.busy?(socket.assigns.admin_jobs), do: @busy_tick, else: @idle_tick
      Process.send_after(self(), :refresh_admin_ambient, delay)
    end

    socket
  end
end
