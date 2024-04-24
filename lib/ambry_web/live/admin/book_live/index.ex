defmodule AmbryWeb.Admin.BookLive.Index do
  @moduledoc """
  LiveView for book admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Books
  alias Ambry.PubSub

  @valid_sort_fields [
    :title,
    :authors,
    :series,
    :published,
    :media,
    :has_description,
    :inserted_at
  ]

  @default_sort "inserted_at.desc"

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      :ok = PubSub.subscribe("book:*")
    end

    {:ok,
     socket
     |> assign(
       page_title: "Books",
       show_header_search: true
     )
     |> maybe_update_books(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_books(params)}
  end

  defp maybe_update_books(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {books, has_more?} = list_books(list_opts, @default_sort)

      assign(socket,
        list_opts: list_opts,
        books: books,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path: ~p"/admin/books?#{next_opts(list_opts)}",
        prev_page_path: ~p"/admin/books?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  defp refresh_books(socket) do
    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    maybe_update_books(socket, params, true)
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    book = Books.get_book!(id)

    case Books.delete_book(book) do
      :ok ->
        {:noreply,
         socket
         |> refresh_books()
         |> put_flash(:info, "Book deleted successfully")}

      {:error, :has_media} ->
        message = """
        Can't delete book because this book has uploaded media.
        You must delete any uploaded media before you can delete this book.
        """

        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_books(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/books?#{patch_opts(list_opts)}")}
  end

  def handle_event("row-click", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/books/#{id}/edit")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/books?#{patch_opts(list_opts)}")}
  end

  defp list_books(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Books.list_books(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :book}, socket), do: {:noreply, refresh_books(socket)}

  defp format_published(%{published_format: :full, published: date}),
    do: Calendar.strftime(date, "%x")

  defp format_published(%{published_format: :year_month, published: date}),
    do: Calendar.strftime(date, "%Y-%m")

  defp format_published(%{published_format: :year, published: date}),
    do: Calendar.strftime(date, "%Y")
end
