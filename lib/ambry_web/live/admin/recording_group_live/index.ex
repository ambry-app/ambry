defmodule AmbryWeb.Admin.RecordingGroupLive.Index do
  @moduledoc """
  LiveView for the recording groups admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.Admin.ReturnTo, only: [query: 1]

  alias Ambry.Media
  alias Ambry.Media.PubSub.RecordingGroupCreated
  alias Ambry.Media.PubSub.RecordingGroupDeleted
  alias Ambry.Media.PubSub.RecordingGroupUpdated
  alias Ambry.Media.RecordingGroup
  alias AmbryWeb.Admin.Deletion

  @valid_sort_fields [
    :name,
    :inserted_at
  ]

  @default_sort "inserted_at.desc"

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      Media.subscribe_to_recording_group_crud_messages()
    end

    {:ok,
     socket
     |> assign(
       page_title: "Sets",
       show_header_search: true
     )
     |> maybe_update_groups(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_groups(params)}
  end

  defp maybe_update_groups(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      load_groups(socket, list_opts)
    else
      socket
    end
  end

  defp load_groups(socket, list_opts) do
    {groups, has_more?, total} = list_groups(list_opts, @default_sort)

    assign(socket,
      list_opts: list_opts,
      groups: groups,
      has_next: has_more?,
      has_prev: list_opts.page > 1,
      page_info: page_info(list_opts, length(groups), total),
      next_page_path: ~p"/admin/sets?#{next_opts(list_opts)}",
      prev_page_path: ~p"/admin/sets?#{prev_opts(list_opts)}",
      current_sort: list_opts.sort || @default_sort
    )
  end

  # The list it is already showing, re-queried, never rebuilt out of string
  # params. Handing `maybe_update_*` a map of `"filter"` and `"page"` and
  # nothing else means a missing `"sort"` parses as `nil`, and since
  # `Map.merge` lets that `nil` win, every PubSub event silently throws the
  # operator's sort away and puts the list back on the default while the
  # address bar goes on claiming the sort they chose.
  defp refresh_groups(socket), do: load_groups(socket, get_list_opts(socket))

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    group = Media.get_recording_group!(id)
    {:ok, message} = Deletion.outcome(Media.delete_recording_group(group), group.name)

    {:noreply, socket |> refresh_groups() |> put_flash(:info, message)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_groups(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/sets?#{patch_opts(list_opts)}")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/sets?#{patch_opts(list_opts)}")}
  end

  # The page and the total, from one set of filters. Counted here rather than
  # in the component so the total can never describe a different query from
  # the rows above it.
  defp list_groups(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    {groups, has_more?} =
      Media.list_recording_groups(
        page_to_offset(opts.page),
        limit(),
        filters,
        sort_to_order(opts.sort || default_sort, @valid_sort_fields)
      )

    {groups, has_more?, Media.count_recording_groups(filters)}
  end

  defp thumbnails(group) do
    group.media
    |> Enum.map(&(&1.thumbnails && &1.thumbnails.small))
    |> Enum.filter(& &1)
    |> Enum.take(3)
  end

  defp book_title(group), do: group.book.title

  defp parts_summary(group) do
    count = length(group.media)
    word = RecordingGroup.part_word_plural(group)

    case group.parts_total do
      nil -> "#{count} #{word}"
      total -> "#{count} of #{total} #{word}"
    end
  end

  @impl Phoenix.LiveView
  def handle_info(%RecordingGroupCreated{}, socket), do: {:noreply, refresh_groups(socket)}
  def handle_info(%RecordingGroupUpdated{}, socket), do: {:noreply, refresh_groups(socket)}
  def handle_info(%RecordingGroupDeleted{}, socket), do: {:noreply, refresh_groups(socket)}

  @doc """
  The list state a row link carries, so the form it opens can come back here
  rather than to the front of an unfiltered, default-sorted page one.
  """
  def return_query(assigns), do: query(assigns.list_opts)
end
