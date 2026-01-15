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

  defp maybe_select_user(socket, nil), do: socket

  defp maybe_select_user(socket, user_id) do
    playthroughs = list_playthroughs_for_user(user_id)

    socket
    |> assign(selected_user_id: user_id, playthroughs: playthroughs)
  end

  defp maybe_select_playthrough(socket, nil), do: socket

  defp maybe_select_playthrough(socket, playthrough_id) do
    playthrough = get_playthrough(playthrough_id)
    playthrough_new = if playthrough, do: get_playthrough_new(playthrough_id)
    events = if playthrough, do: list_events_for_playthrough(playthrough_id), else: []

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
    from(p in Ambry.Playback.Playthrough,
      where: p.user_id == ^user_id,
      order_by: [desc: p.updated_at],
      preload: [media: :book]
    )
    |> Repo.all()
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
    cond do
      playthrough.deleted_at ->
        "rounded px-1 bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

      playthrough.status == :in_progress ->
        "rounded px-1 bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

      playthrough.status == :finished ->
        "rounded px-1 bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

      playthrough.status == :abandoned ->
        "rounded px-1 bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

      true ->
        "rounded px-1 bg-zinc-100 text-zinc-800 dark:bg-zinc-700 dark:text-zinc-200"
    end
  end

  defp status_label(playthrough) do
    if playthrough.deleted_at, do: "deleted", else: playthrough.status
  end

  defp event_type_badge_class(type) when type in [:play, :pause, :seek, :rate_change],
    do: "rounded px-1 text-xs bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

  defp event_type_badge_class(type) when type in [:start, :finish, :abandon, :resume],
    do:
      "rounded px-1 text-xs bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200"

  defp event_type_badge_class(_type),
    do: "rounded px-1 text-xs bg-zinc-100 text-zinc-800 dark:bg-zinc-700 dark:text-zinc-200"
end
