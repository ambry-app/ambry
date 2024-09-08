defmodule AmbryWeb.Admin.PersonLive.Index do
  @moduledoc """
  LiveView for person admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.People
  alias Ambry.PubSub

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
      :ok = PubSub.subscribe("person:*")
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
      {people, has_more?} = list_people(list_opts, @default_sort)

      assign(socket,
        list_opts: list_opts,
        people: people,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path: ~p"/admin/people?#{next_opts(list_opts)}",
        prev_page_path: ~p"/admin/people?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  defp refresh_people(socket) do
    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    maybe_update_people(socket, params, true)
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    person = People.get_person!(id)

    case People.delete_person(person) do
      :ok ->
        {:noreply,
         socket
         |> refresh_people()
         |> put_flash(:info, "Deleted #{person.name}")}

      {:error, {:has_authored_books, books}} ->
        message = """
        Can't delete person because they have authored the following books:
        #{Enum.join(books, ", ")}.
        You must delete the books before you can delete this person.
        """

        {:noreply, put_flash(socket, :error, message)}

      {:error, {:has_narrated_books, books}} ->
        message = """
        Can't delete person because they have narrated the following books:
        #{Enum.join(books, ", ")}.
        You must delete the books before you can delete this person.
        """

        {:noreply, put_flash(socket, :error, message)}
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

  defp list_people(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    People.list_people(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :person}, socket), do: {:noreply, refresh_people(socket)}
end
