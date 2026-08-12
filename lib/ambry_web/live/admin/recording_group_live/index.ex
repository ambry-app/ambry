defmodule AmbryWeb.Admin.RecordingGroupLive.Index do
  @moduledoc """
  LiveView for the recording groups admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Media
  alias Ambry.Media.PubSub.RecordingGroupCreated
  alias Ambry.Media.PubSub.RecordingGroupDeleted
  alias Ambry.Media.PubSub.RecordingGroupUpdated
  alias Ambry.Media.RecordingGroup

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
      {groups, has_more?} = list_groups(list_opts, @default_sort)

      assign(socket,
        list_opts: list_opts,
        groups: groups,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path: ~p"/admin/sets?#{next_opts(list_opts)}",
        prev_page_path: ~p"/admin/sets?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  defp refresh_groups(socket) do
    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    maybe_update_groups(socket, params, true)
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    group = Media.get_recording_group!(id)
    {:ok, _group} = Media.delete_recording_group(group)

    {:noreply,
     socket
     |> refresh_groups()
     |> put_flash(:info, "Set deleted successfully")}
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

  defp list_groups(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Media.list_recording_groups(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
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
end
