defmodule AmbryWeb.Admin.SeriesLive.Index do
  @moduledoc """
  LiveView for series admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.PubSub
  alias Ambry.Series

  @valid_sort_fields [
    :name,
    :authors,
    :books,
    :inserted_at
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      :ok = PubSub.subscribe("series:*")
    end

    {:ok,
     socket
     |> assign(page_title: "Series", default_sort: "inserted_at.desc")
     |> maybe_update_series(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, maybe_update_series(socket, params)}
  end

  defp maybe_update_series(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {series, has_more?} = list_series(list_opts, socket.assigns.default_sort)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:series, series)
    else
      socket
    end
  end

  defp refresh_series(socket) do
    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    maybe_update_series(socket, params, true)
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    series = Series.get_series!(id)
    {:ok, _} = Series.delete_series(series)

    {:noreply,
     socket
     |> refresh_series()
     |> put_flash(:info, "Series deleted successfully")}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_series(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/series?#{patch_opts(list_opts)}")}
  end

  def handle_event("row-click", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/series/#{id}/edit")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/series?#{patch_opts(list_opts)}")}
  end

  defp list_series(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Series.list_series(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :series}, socket), do: {:noreply, refresh_series(socket)}
end
