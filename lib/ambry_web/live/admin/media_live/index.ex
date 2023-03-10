defmodule AmbryWeb.Admin.MediaLive.Index do
  @moduledoc """
  LiveView for media admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.TimeUtils

  alias Ambry.{Media, PubSub}

  alias AmbryWeb.Admin.MediaLive.{ChaptersComponent, FormComponent}

  @valid_sort_fields [
    :book
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      :ok = PubSub.subscribe("media:*")
    end

    {:ok,
     socket
     |> assign(:header_title, "Media")
     |> set_in_progress_media()
     |> maybe_update_media(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> maybe_update_media(params)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    media = Media.get_media!(id)

    socket
    |> assign(:page_title, media.book.title)
    |> assign(:selected_media, media)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Media")
    |> assign(:selected_media, %Media.Media{media_narrators: []})
  end

  defp apply_action(socket, :chapters, %{"id" => id}) do
    media = Media.get_media!(id)

    socket
    |> assign(:page_title, "#{media.book.title} - Chapters")
    |> assign(:selected_media, media)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Media")
    |> assign(:selected_media, nil)
  end

  defp maybe_update_media(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {media, has_more?} = list_media(list_opts)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:media, media)
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

    socket
    |> maybe_update_media(params, true)
    |> set_in_progress_media()
  end

  defp set_in_progress_media(socket) do
    known_processing_media = Map.get(socket.assigns, :processing_media, [])
    progress_map = Map.get(socket.assigns, :processing_media_progress_map, %{})

    {current_processing_media, _has_more?} =
      Media.list_media(0, 999, %{status: :processing}, desc: :inserted_at)

    to_add = Enum.map(current_processing_media -- known_processing_media, & &1.id)
    to_remove = Enum.map(known_processing_media -- current_processing_media, & &1.id)

    progress_map = Map.drop(progress_map, to_remove)

    Enum.each(to_add, &(:ok = PubSub.subscribe("media-progress:#{&1}")))
    Enum.each(to_remove, &(:ok = PubSub.unsubscribe("media-progress:#{&1}")))

    assign(socket, %{
      processing_media: current_processing_media,
      processing_media_progress_map: progress_map
    })
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

  def handle_event("row-click", %{"id" => id}, socket) do
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/media/#{id}/edit?#{patch_opts(list_opts)}")}
  end

  defp list_media(opts) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Media.list_media(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort, @valid_sort_fields)
    )
  end

  # handle chapter extraction strategy from chapters component
  @impl Phoenix.LiveView
  def handle_info({:run_strategy, strategy}, socket) do
    %{selected_media: media} = socket.assigns

    case strategy.get_chapters(media) do
      {:ok, chapters} ->
        send_update(ChaptersComponent,
          id: media.id,
          chapters: {:ok, chapters}
        )

      {:error, error} ->
        send_update(ChaptersComponent,
          id: media.id,
          chapters: {:error, error}
        )
    end

    {:noreply, socket}
  end

  def handle_info(%PubSub.Message{type: :media, action: :progress} = message, socket) do
    %{id: media_id, meta: %{progress: progress}} = message

    progress_map =
      socket.assigns
      |> Map.get(:processing_media_progress_map, %{})
      |> Map.put(media_id, progress)

    {:noreply, assign(socket, :processing_media_progress_map, progress_map)}
  end

  def handle_info(%PubSub.Message{type: :media}, socket), do: {:noreply, refresh_media(socket)}

  defp status_color(:pending), do: :yellow
  defp status_color(:processing), do: :blue
  defp status_color(:error), do: :red
  defp status_color(:ready), do: :brand

  defp progress_percent(nil), do: "0.0"

  defp progress_percent(%Decimal{} = progress) do
    progress
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end
end
