defmodule AmbryWeb.Admin.PlaybackDebugLive.Index do
  @moduledoc """
  Admin debug view for playthroughs and playback events.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Accounts
  alias Ambry.Playback
  alias Ambry.Playback.PlaythroughFlat
  alias AmbryWeb.Admin.PlaybackDebugLive.EventsModal

  @valid_sort_fields [
    :book_title,
    :status,
    :progress_percent,
    :last_event_at,
    :started_at
  ]

  @default_sort "last_event_at.desc"

  @impl Phoenix.LiveView
  def mount(%{"user_id" => user_id} = params, _session, socket) do
    user = Accounts.get_user!(user_id)

    socket =
      socket
      |> assign(
        page_title: "Playthroughs for #{user.email}",
        selected_user: user,
        playthroughs: [],
        selected_playthrough: nil,
        show_header_search: true,
        has_next: false,
        has_prev: false,
        next_page_path: "#",
        prev_page_path: "#",
        current_sort: @default_sort,
        list_opts: %{page: 1, filter: nil, sort: nil}
      )
      |> maybe_update_playthroughs(params, true)

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_select_playthrough(params["playthrough_id"])
     |> maybe_update_playthroughs(params, true)}
  end

  defp maybe_select_playthrough(socket, nil) do
    assign(socket, selected_playthrough: nil)
  end

  defp maybe_select_playthrough(socket, playthrough_id) do
    playthrough = Playback.get_playthrough_new(playthrough_id)
    assign(socket, selected_playthrough: playthrough)
  end

  defp maybe_update_playthroughs(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {playthroughs, has_more?} = list_playthroughs(socket.assigns.selected_user.id, list_opts)

      assign(socket,
        list_opts: list_opts,
        playthroughs: playthroughs,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path:
          ~p"/admin/users/#{socket.assigns.selected_user.id}/playthroughs?#{next_opts(list_opts)}",
        prev_page_path:
          ~p"/admin/users/#{socket.assigns.selected_user.id}/playthroughs?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_playthroughs(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)
    user_id = socket.assigns.selected_user.id

    {:noreply,
     push_patch(socket,
       to: ~p"/admin/users/#{user_id}/playthroughs?#{patch_opts(list_opts)}"
     )}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    user_id = socket.assigns.selected_user.id

    {:noreply,
     push_patch(socket,
       to: ~p"/admin/users/#{user_id}/playthroughs?#{patch_opts(list_opts)}"
     )}
  end

  defp list_playthroughs(user_id, opts) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}
    filters = Map.put(filters, :user_id, user_id)

    Playback.list_playthroughs_flat(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || @default_sort, @valid_sort_fields)
    )
  end

  defp format_date(nil), do: "-"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%x")
  end

  defp format_full_datetime(nil), do: nil

  defp format_full_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp playthrough_label(%PlaythroughFlat{book_title: title}), do: title

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
end
