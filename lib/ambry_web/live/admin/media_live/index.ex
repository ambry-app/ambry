defmodule AmbryWeb.Admin.MediaLive.Index do
  @moduledoc """
  LiveView for media admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.TimeUtils

  alias Ambry.Media
  alias Ambry.Media.PubSub.MediaCreated
  alias Ambry.Media.PubSub.MediaDeleted
  alias Ambry.Media.PubSub.MediaUpdated

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

  # The overview counts recordings that need something done to them, and a
  # count the operator can't open is half an answer — so each one links here
  # with the name of the trouble, and the page says which list it is showing
  # and how to leave it. Named rather than expressed as raw field filters:
  # the URL is a thing the operator sees, and `?problem=missing` survives
  # being pasted into a note in a way `?direct_play=false` doesn't.
  @problems %{
    "missing" => %{
      filters: %{missing: true},
      words: "Files couldn't be read",
      empty: "Every audiobook's files are where they should be."
    },
    "error" => %{
      filters: %{status: :error},
      words: "Processing failed",
      empty: "Nothing failed processing."
    },
    "streaming" => %{
      filters: %{direct_play: false},
      words: "Streaming only",
      empty: "Every audiobook is direct-play."
    }
  }

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      Media.subscribe_to_media_crud_messages()
    end

    {:ok,
     socket
     |> assign(
       page_title: "Audiobooks",
       show_header_search: true
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
    old_list_opts = socket |> get_list_opts() |> Map.put_new(:problem, nil)
    new_list_opts = params |> get_list_opts() |> Map.put(:problem, parse_problem(params))
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {media, has_more?} = list_media(list_opts, @default_sort)

      assign(socket,
        list_opts: list_opts,
        media: media,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path: ~p"/admin/audiobooks?#{next_opts(list_opts)}",
        prev_page_path: ~p"/admin/audiobooks?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  # Every rebuild goes back through params, so anything the page is currently
  # narrowed by has to be restated here or it is silently dropped — a search
  # inside "Files couldn't be read" would quietly widen to the whole library.
  defp refresh_media(socket) do
    list_opts = get_list_opts(socket)

    maybe_update_media(socket, current_params(list_opts), true)
  end

  defp current_params(list_opts, overrides \\ %{}) do
    %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page),
      "problem" => to_string(list_opts[:problem])
    }
    |> Map.merge(overrides)
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    media = Media.get_media!(id)
    {:ok, _media} = Media.delete_media(media)

    {:noreply, refresh_media(socket)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    params =
      socket
      |> get_list_opts()
      |> current_params(%{"filter" => query, "page" => "1"})

    socket = maybe_update_media(socket, params)
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/audiobooks?#{patch_opts(list_opts)}")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/audiobooks?#{patch_opts(list_opts)}")}
  end

  defp list_media(opts, default_sort) do
    filters =
      if opts.filter, do: %{search: opts.filter}, else: %{}

    filters = Map.merge(filters, problem_filters(opts[:problem]))

    Media.list_media(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
  end

  @impl Phoenix.LiveView
  def handle_info(%MediaCreated{}, socket), do: {:noreply, refresh_media(socket)}
  def handle_info(%MediaUpdated{}, socket), do: {:noreply, refresh_media(socket)}
  def handle_info(%MediaDeleted{}, socket), do: {:noreply, refresh_media(socket)}

  defp parse_problem(params) do
    problem = params |> Map.get("problem", "") |> String.trim()

    if Map.has_key?(@problems, problem), do: problem
  end

  defp problem_filters(problem) when is_map_key(@problems, problem),
    do: @problems[problem].filters

  defp problem_filters(_none), do: %{}

  @doc """
  What the page is narrowed to, for the chip that says so.

  A filter arriving from another page has to announce itself: the operator
  clicked a number on the overview and landed on a list that is missing most
  of the library, and nothing else on this page would explain why.
  """
  def problem_words(problem) when is_map_key(@problems, problem), do: @problems[problem].words
  def problem_words(_none), do: nil

  @doc """
  What an empty *filtered* list means.

  "No audiobooks yet. Create one." is a lie under a filter — there are
  hundreds, they just aren't broken — and it offers the one action that has
  nothing to do with why the page is empty.
  """
  def problem_empty_words(problem) when is_map_key(@problems, problem),
    do: @problems[problem].empty

  def problem_empty_words(_none), do: nil

  defp status_color(:pending), do: :yellow
  defp status_color(:processing), do: :blue
  defp status_color(:error), do: :red
end
