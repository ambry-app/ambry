defmodule AmbryWeb.Admin.PlaybackDebugLive.Index do
  @moduledoc """
  Admin debug view for playthroughs and playback events.
  """

  use AmbryWeb, :admin_live_view

  import Ecto.Query

  alias Ambry.Accounts
  alias Ambry.Repo

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    users = Accounts.list_all_users_for_select()

    {:ok,
     socket
     |> assign(
       page_title: "Playback Debug",
       users: users,
       selected_user_id: nil,
       playthroughs: [],
       player_states_count: nil,
       selected_playthrough: nil,
       selected_playthrough_new: nil,
       events: []
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> maybe_select_user(params["user_id"])
      |> maybe_select_playthrough(params["playthrough_id"])

    {:noreply, socket}
  end

  defp maybe_select_user(socket, user_id) do
    socket =
      if user_id != socket.assigns.selected_user_id do
        assign(socket,
          selected_playthrough: nil,
          selected_playthrough_new: nil,
          events: []
        )
      else
        socket
      end

    if user_id in [nil, ""] do
      socket
      |> assign(
        selected_user_id: nil,
        playthroughs: [],
        player_states_count: nil
      )
    else
      playthroughs = list_playthroughs_for_user(user_id)
      player_states_count = count_player_states_for_user(user_id)

      socket
      |> assign(
        selected_user_id: user_id,
        playthroughs: playthroughs,
        player_states_count: player_states_count
      )
    end
  end

  defp maybe_select_playthrough(socket, nil), do: socket

  defp maybe_select_playthrough(socket, playthrough_id) do
    playthrough_new = get_playthrough_new(playthrough_id)
    playthrough = if playthrough_new, do: get_playthrough(playthrough_id)
    events = if playthrough_new, do: list_events_for_playthrough(playthrough_id), else: []

    socket
    |> assign(
      selected_playthrough: playthrough,
      selected_playthrough_new: playthrough_new,
      events: events
    )
  end

  @impl Phoenix.LiveView
  def handle_event("select_user", %{"user_id" => user_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/playback-debug?user_id=#{user_id}")}
  end

  def handle_event("select_playthrough", %{"id" => playthrough_id}, socket) do
    user_id = socket.assigns.selected_user_id

    {:noreply,
     push_patch(socket,
       to: ~p"/admin/playback-debug?user_id=#{user_id}&playthrough_id=#{playthrough_id}"
     )}
  end

  defp list_playthroughs_for_user(user_id) do
    from(p in Ambry.Playback.PlaythroughNew,
      where: p.user_id == ^user_id,
      order_by: [desc: p.last_event_at],
      preload: [media: :book]
    )
    |> Repo.all()
  end

  defp count_player_states_for_user(user_id) do
    from(ps in Ambry.Media.PlayerState,
      where: ps.user_id == ^user_id,
      select: count(ps.id)
    )
    |> Repo.one()
  end

  defp get_playthrough(id) do
    from(p in Ambry.Playback.Playthrough,
      where: p.id == ^id,
      preload: [[media: :book], :user]
    )
    |> Repo.one()
  end

  defp get_playthrough_new(id) do
    from(p in Ambry.Playback.PlaythroughNew,
      where: p.id == ^id,
      preload: [[media: :book], :user]
    )
    |> Repo.one()
  end

  defp list_events_for_playthrough(playthrough_id) do
    from(e in Ambry.Playback.PlaybackEvent,
      where: e.playthrough_id == ^playthrough_id,
      order_by: [desc: e.timestamp],
      preload: [:device]
    )
    |> Repo.all()
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S.%f")
  end

  defp playthrough_label(playthrough) do
    case playthrough.media do
      nil -> "Unknown media"
      %{book: %{title: title}} -> title
      media -> "Media #{media.id}"
    end
  end

  defp status_badge_class(playthrough) do
    case playthrough.status do
      :deleted ->
        "rounded px-1 bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

      :in_progress ->
        "rounded px-1 bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

      :finished ->
        "rounded px-1 bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

      :abandoned ->
        "rounded px-1 bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

      _ ->
        "rounded px-1 bg-zinc-100 text-zinc-800 dark:bg-zinc-700 dark:text-zinc-200"
    end
  end

  defp status_label(playthrough) do
    playthrough.status
  end

  defp event_type_badge_class(type) when type in [:play, :pause, :seek, :rate_change],
    do: "rounded px-1 text-xs bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

  defp event_type_badge_class(type) when type in [:start, :finish, :abandon, :resume],
    do:
      "rounded px-1 text-xs bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200"

  defp event_type_badge_class(_type),
    do: "rounded px-1 text-xs bg-zinc-100 text-zinc-800 dark:bg-zinc-700 dark:text-zinc-200"

  # Discrepancy highlighting helpers

  @discrepancy_class "bg-red-100 text-red-900 dark:bg-red-900/50 dark:text-red-200"

  defp discrepancy_class(nil, _new_val), do: nil
  defp discrepancy_class(_old_val, nil), do: nil

  defp discrepancy_class(%DateTime{} = old_val, %DateTime{} = new_val) do
    if !datetimes_match?(old_val, new_val), do: @discrepancy_class
  end

  defp discrepancy_class(old_val, new_val) do
    if !values_match?(old_val, new_val), do: @discrepancy_class
  end

  defp datetimes_match?(dt1, dt2) do
    abs(DateTime.diff(dt1, dt2, :millisecond)) <= 1000
  end

  defp values_match?(val, val), do: true
  defp values_match?(_, _), do: false

  # Device display helpers

  defp format_device(nil), do: nil

  defp format_device(device) do
    case device.type do
      :web -> format_web_device(device)
      _ -> format_mobile_device(device)
    end
  end

  defp format_mobile_device(device) do
    model = device.model_name || device.brand || to_string(device.type)
    os = format_os(device.os_name, device.os_version)
    app = format_app_version(device.app_version, device.app_build)

    [model, os, app]
    |> Enum.filter(& &1)
    |> Enum.join(" / ")
  end

  defp format_web_device(device) do
    browser = format_browser(device.browser, device.browser_version)
    os = device.os_name

    case {browser, os} do
      {nil, nil} -> "Web"
      {nil, os} -> "Web (#{os})"
      {browser, nil} -> browser
      {browser, os} -> "#{browser} (#{os})"
    end
  end

  defp format_os(nil, _), do: nil
  defp format_os(name, nil), do: name
  defp format_os(name, version), do: "#{name} #{version}"

  defp format_browser(nil, _), do: nil
  defp format_browser(name, nil), do: name
  defp format_browser(name, version), do: "#{name} #{version}"

  defp format_app_version(nil, nil), do: nil
  defp format_app_version(version, nil), do: "v#{version}"
  defp format_app_version(nil, build), do: "build #{build}"
  defp format_app_version(version, build), do: "v#{version} (#{build})"
end
