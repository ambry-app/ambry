defmodule AmbryWeb.Admin.SeriesLive.Index do
  @moduledoc """
  LiveView for series admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Series

  alias AmbryWeb.Admin.SeriesLive.FormComponent

  @valid_sort_fields [
    :name
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:header_title, "Series")
     |> maybe_update_series(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> maybe_update_series(params)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    series = Series.get_series!(id)

    socket
    |> assign(:page_title, series.name)
    |> assign(:selected_series, series)
    |> assign(:autofocus_search, false)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Series")
    |> assign(:selected_series, %Series.Series{series_books: []})
    |> assign(:autofocus_search, false)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Series")
    |> assign(:selected_series, nil)
    |> assign_new(:autofocus_search, fn -> false end)
  end

  defp maybe_update_series(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {series, has_more?} = list_series(list_opts)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:series, series)
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    series = Series.get_series!(id)
    {:ok, _} = Series.delete_series(series)

    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    {:noreply, maybe_update_series(socket, params, true)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> maybe_update_series(%{"filter" => query, "page" => "1"})
      |> assign(:autofocus_search, true)

    list_opts = get_list_opts(socket)

    {:noreply,
     push_patch(socket,
       to: Routes.admin_series_index_path(socket, :index, patch_opts(list_opts))
     )}
  end

  def handle_event("row-click", %{"id" => id}, socket) do
    list_opts = get_list_opts(socket)

    {:noreply,
     push_patch(socket,
       to: Routes.admin_series_index_path(socket, :edit, id, patch_opts(list_opts))
     )}
  end

  defp list_series(opts) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Series.list_series(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort, @valid_sort_fields)
    )
  end
end
