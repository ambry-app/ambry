defmodule AmbryWeb.Admin.UniverseLive.Index do
  @moduledoc """
  LiveView for universes admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Books
  alias Ambry.Books.PubSub.UniverseCreated
  alias Ambry.Books.PubSub.UniverseDeleted
  alias Ambry.Books.PubSub.UniverseUpdated

  @valid_sort_fields [
    :name,
    :books,
    :inserted_at
  ]

  @default_sort "inserted_at.desc"

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      Books.subscribe_to_universe_crud_messages()
    end

    {:ok,
     socket
     |> assign(
       page_title: "Universes",
       show_header_search: true
     )
     |> maybe_update_universes(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_universes(params)}
  end

  defp maybe_update_universes(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      load_universes(socket, list_opts)
    else
      socket
    end
  end

  defp load_universes(socket, list_opts) do
    {universes, has_more?, total} = list_universes(list_opts, @default_sort)

    assign(socket,
      list_opts: list_opts,
      universes: universes,
      has_next: has_more?,
      has_prev: list_opts.page > 1,
      page_info: page_info(list_opts, length(universes), total),
      next_page_path: ~p"/admin/universes?#{next_opts(list_opts)}",
      prev_page_path: ~p"/admin/universes?#{prev_opts(list_opts)}",
      current_sort: list_opts.sort || @default_sort
    )
  end

  # The list it is already showing, re-queried — not rebuilt out of string
  # params. It used to hand `maybe_update_*` a map of `"filter"` and `"page"`
  # and nothing else, and since a missing `"sort"` parses as `nil` and
  # `Map.merge` lets the new `nil` win, every PubSub event silently threw the
  # operator's sort away and put the list back on the default — while the
  # address bar went on claiming the sort they had chosen.
  defp refresh_universes(socket), do: load_universes(socket, get_list_opts(socket))

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    universe = Books.get_universe!(id)
    {:ok, _universe} = Books.delete_universe(universe)

    {:noreply,
     socket
     |> refresh_universes()
     |> put_flash(:info, "Universe deleted successfully")}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_universes(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/universes?#{patch_opts(list_opts)}")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/universes?#{patch_opts(list_opts)}")}
  end

  # The page and the total, from one set of filters. Counted here rather than
  # in the component so the "of 435" can never describe a different query from
  # the rows above it.
  defp list_universes(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    {universes, has_more?} =
      Books.list_universes(
        page_to_offset(opts.page),
        limit(),
        filters,
        sort_to_order(opts.sort || default_sort, @valid_sort_fields)
      )

    {universes, has_more?, Books.count_universes(filters)}
  end

  @impl Phoenix.LiveView
  def handle_info(%UniverseCreated{}, socket), do: {:noreply, refresh_universes(socket)}
  def handle_info(%UniverseUpdated{}, socket), do: {:noreply, refresh_universes(socket)}
  def handle_info(%UniverseDeleted{}, socket), do: {:noreply, refresh_universes(socket)}
end
