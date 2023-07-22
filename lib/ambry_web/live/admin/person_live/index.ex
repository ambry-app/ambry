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
    :is_author,
    :authored_books,
    :is_narrator,
    :narrated_media
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      :ok = PubSub.subscribe("person:*")
    end

    {:ok,
     socket
     |> assign(page_title: "Authors & Narrators")
     |> maybe_update_people(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, maybe_update_people(socket, params)}
  end

  defp maybe_update_people(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {people, has_more?} = list_people(list_opts)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:people, people)
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

  def handle_event("row-click", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/people/#{id}/edit")}
  end

  defp list_people(opts) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    People.list_people(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort, @valid_sort_fields)
    )
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :person}, socket), do: {:noreply, refresh_people(socket)}
end
