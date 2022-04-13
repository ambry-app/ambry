defmodule AmbryWeb.Admin.BookLive.Index do
  @moduledoc """
  LiveView for book admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Books
  alias Ambry.Books.Book

  alias AmbryWeb.Admin.BookLive.FormComponent

  @valid_sort_fields [
    :title
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:header_title, "Books")
     |> maybe_update_books(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> maybe_update_books(params)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    book = Books.get_book!(id)

    socket
    |> assign(:page_title, book.title)
    |> assign(:book, book)
    |> assign(:autofocus_search, false)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Book")
    |> assign(:book, %Book{book_authors: [], series_books: []})
    |> assign(:autofocus_search, false)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Books")
    |> assign(:book, nil)
    |> assign_new(:autofocus_search, fn -> false end)
  end

  defp maybe_update_books(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {books, has_more?} = list_books(list_opts)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:books, books)
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    book = Books.get_book!(id)

    case Books.delete_book(book) do
      :ok ->
        list_opts = get_list_opts(socket)

        params = %{
          "filter" => to_string(list_opts.filter),
          "page" => to_string(list_opts.page)
        }

        {:noreply,
         socket
         |> maybe_update_books(params, true)
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
    socket =
      socket
      |> maybe_update_books(%{"filter" => query, "page" => "1"})
      |> assign(:autofocus_search, true)

    list_opts = get_list_opts(socket)

    {:noreply,
     push_patch(socket, to: Routes.admin_book_index_path(socket, :index, patch_opts(list_opts)))}
  end

  def handle_event("row-click", %{"id" => id}, socket) do
    list_opts = get_list_opts(socket)

    {:noreply,
     push_patch(socket,
       to: Routes.admin_book_index_path(socket, :edit, id, patch_opts(list_opts))
     )}
  end

  defp list_books(opts) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Books.list_books(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort, @valid_sort_fields)
    )
  end
end
