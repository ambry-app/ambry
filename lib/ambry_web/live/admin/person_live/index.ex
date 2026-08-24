defmodule AmbryWeb.Admin.PersonLive.Index do
  @moduledoc """
  LiveView for person admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.Admin.ReturnTo, only: [query: 1]

  alias Ambry.People
  alias Ambry.People.PubSub.PersonCreated
  alias Ambry.People.PubSub.PersonDeleted
  alias Ambry.People.PubSub.PersonUpdated
  alias AmbryWeb.Admin.Deletion

  @valid_sort_fields [
    :name,
    :authored_books,
    :narrated_media,
    :has_description,
    :inserted_at
  ]

  @default_sort "inserted_at.desc"

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      People.subscribe_to_person_crud_messages()
    end

    {:ok,
     socket
     |> assign(
       page_title: "Authors & Narrators",
       show_header_search: true
     )
     |> maybe_update_people(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_people(params)}
  end

  defp maybe_update_people(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      load_people(socket, list_opts)
    else
      socket
    end
  end

  defp load_people(socket, list_opts) do
    {people, has_more?, total} = list_people(list_opts, @default_sort)

    assign(socket,
      list_opts: list_opts,
      people: people,
      has_next: has_more?,
      has_prev: list_opts.page > 1,
      page_info: page_info(list_opts, length(people), total),
      next_page_path: ~p"/admin/people?#{next_opts(list_opts)}",
      prev_page_path: ~p"/admin/people?#{prev_opts(list_opts)}",
      current_sort: list_opts.sort || @default_sort
    )
  end

  # The list it is already showing, re-queried, never rebuilt out of string
  # params. Handing `maybe_update_*` a map of `"filter"` and `"page"` and
  # nothing else means a missing `"sort"` parses as `nil`, and since
  # `Map.merge` lets that `nil` win, every PubSub event silently throws the
  # operator's sort away and puts the list back on the default while the
  # address bar goes on claiming the sort they chose.
  defp refresh_people(socket), do: load_people(socket, get_list_opts(socket))

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    person = People.get_person!(id)

    case Deletion.outcome(People.delete_person(person), person.name) do
      {:ok, message} -> {:noreply, socket |> refresh_people() |> put_flash(:info, message)}
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_people(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/people?#{patch_opts(list_opts)}")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/people?#{patch_opts(list_opts)}")}
  end

  # The page and the total, from one set of filters. Counted here rather than
  # in the component so the total can never describe a different query from
  # the rows above it.
  defp list_people(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    {people, has_more?} =
      People.list_people(
        page_to_offset(opts.page),
        limit(),
        filters,
        sort_to_order(opts.sort || default_sort, @valid_sort_fields)
      )

    {people, has_more?, People.count_people(filters)}
  end

  @impl Phoenix.LiveView
  def handle_info(%PersonCreated{}, socket), do: {:noreply, refresh_people(socket)}
  def handle_info(%PersonUpdated{}, socket), do: {:noreply, refresh_people(socket)}
  def handle_info(%PersonDeleted{}, socket), do: {:noreply, refresh_people(socket)}

  @doc """
  The list state a row link carries, so the form it opens can come back here
  rather than to the front of an unfiltered, default-sorted page one.
  """
  def return_query(assigns), do: query(assigns.list_opts)
end
