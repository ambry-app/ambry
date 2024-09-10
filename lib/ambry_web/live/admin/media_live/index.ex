defmodule AmbryWeb.Admin.MediaLive.Index do
  @moduledoc """
  LiveView for media admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.TimeUtils

  alias Ambry.Media
  alias Ambry.PubSub

  @valid_sort_fields [
    :status,
    :book,
    :series,
    :authors,
    :narrators,
    :duration,
    :published,
    :inserted_at
  ]

  @default_sort "inserted_at.desc"

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      :ok = PubSub.subscribe("media:*")
      :ok = PubSub.subscribe("media-progress")
    end

    {:ok,
     socket
     |> assign(
       page_title: "Media",
       show_header_search: true,
       processing_media_progress_map: %{}
     )
     |> maybe_update_media(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_media(params)}
  end

  defp maybe_update_media(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {media, has_more?} = list_media(list_opts, @default_sort)

      assign(socket,
        list_opts: list_opts,
        media: media,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path: ~p"/admin/media?#{next_opts(list_opts)}",
        prev_page_path: ~p"/admin/media?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  defp refresh_media(socket) do
    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    maybe_update_media(socket, params, true)
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    media = Media.get_media!(id)
    :ok = Media.delete_media(media)

    {:noreply, refresh_media(socket)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_media(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/media?#{patch_opts(list_opts)}")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/media?#{patch_opts(list_opts)}")}
  end

  defp list_media(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Media.list_media(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
  end

  @impl Phoenix.LiveView

  def handle_info(%PubSub.Message{type: :media, action: :progress} = message, socket) do
    %{id: media_id, meta: %{progress: progress}} = message

    # NOTE: technically this map will just fill up over time, but it's bounded
    # by the total number of media, and it's only a number, so no big deal.
    {:noreply, update(socket, :processing_media_progress_map, &Map.put(&1, media_id, progress))}
  end

  def handle_info(%PubSub.Message{type: :media}, socket), do: {:noreply, refresh_media(socket)}

  defp status_color(:pending), do: :yellow
  defp status_color(:processing), do: :blue
  defp status_color(:error), do: :red
  defp status_color(:ready), do: :brand

  defp processing_progress_percent(nil), do: "0.0"

  defp processing_progress_percent(%Decimal{} = progress) do
    progress
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end
end
