defmodule AmbryWeb.Admin.SeriesLive.Index do
  @moduledoc """
  LiveView for series admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.Admin.ReturnTo, only: [query: 1]

  alias Ambry.Books
  alias Ambry.Books.PubSub.SeriesCreated
  alias Ambry.Books.PubSub.SeriesDeleted
  alias Ambry.Books.PubSub.SeriesUpdated
  alias AmbryWeb.Admin.Deletion

  @valid_sort_fields [
    :name,
    :authors,
    :books,
    :inserted_at
  ]

  @default_sort "inserted_at.desc"

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      Books.subscribe_to_series_crud_messages()
    end

    {:ok,
     socket
     |> assign(
       page_title: "Series",
       show_header_search: true
     )
     |> maybe_update_series(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_series(params)}
  end

  defp maybe_update_series(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      load_series(socket, list_opts)
    else
      socket
    end
  end

  defp load_series(socket, list_opts) do
    {series, has_more?, total} = list_series(list_opts, @default_sort)

    assign(socket,
      list_opts: list_opts,
      series: series,
      has_next: has_more?,
      has_prev: list_opts.page > 1,
      page_info: page_info(list_opts, length(series), total),
      next_page_path: ~p"/admin/series?#{next_opts(list_opts)}",
      prev_page_path: ~p"/admin/series?#{prev_opts(list_opts)}",
      current_sort: list_opts.sort || @default_sort
    )
  end

  # The list it is already showing, re-queried, never rebuilt out of string
  # params. Handing `maybe_update_*` a map of `"filter"` and `"page"` and
  # nothing else means a missing `"sort"` parses as `nil`, and since
  # `Map.merge` lets that `nil` win, every PubSub event silently throws the
  # operator's sort away and puts the list back on the default while the
  # address bar goes on claiming the sort they chose.
  defp refresh_series(socket), do: load_series(socket, get_list_opts(socket))

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    series = Books.get_series!(id)
    {:ok, message} = Deletion.outcome(Books.delete_series(series), series.name)

    {:noreply, socket |> refresh_series() |> put_flash(:info, message)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_series(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/series?#{patch_opts(list_opts)}")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/series?#{patch_opts(list_opts)}")}
  end

  # The page and the total, from one set of filters. Counted here rather than
  # in the component so the total can never describe a different query from
  # the rows above it.
  defp list_series(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    {series, has_more?} =
      Books.list_series(
        page_to_offset(opts.page),
        limit(),
        filters,
        sort_to_order(opts.sort || default_sort, @valid_sort_fields)
      )

    {series, has_more?, Books.count_series(filters)}
  end

  @impl Phoenix.LiveView
  def handle_info(%SeriesCreated{}, socket), do: {:noreply, refresh_series(socket)}
  def handle_info(%SeriesUpdated{}, socket), do: {:noreply, refresh_series(socket)}
  def handle_info(%SeriesDeleted{}, socket), do: {:noreply, refresh_series(socket)}

  @doc """
  The list state a row link carries, so the form it opens can come back here
  rather than to the front of an unfiltered, default-sorted page one.
  """
  def return_query(assigns), do: query(assigns.list_opts)
end
