defmodule AmbryWeb.Admin.BookLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.People
  alias AmbryWeb.Admin.BookLive.Form.AudibleImportForm
  alias AmbryWeb.Admin.BookLive.Form.GoodreadsImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(
       import: nil,
       scraping_available: AmbryScraping.web_scraping_available?(),
       authors: People.authors_for_select(),
       series: Books.series_for_select()
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    book = Books.get_book!(id)
    changeset = Books.change_book(book)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: book.title,
      book: book
    )
  end

  defp apply_action(socket, :new, _params) do
    book = %Book{book_authors: [], series_books: []}
    changeset = Books.change_book(book)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Book",
      book: book
    )
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, handle_import_form_params(socket, params)}
  end

  defp handle_import_form_params(socket, %{"import" => type}) do
    query = socket.assigns.form.params["title"] || socket.assigns.book.title
    import_type = String.to_existing_atom(type)
    assign(socket, import: %{type: import_type, query: query})
  end

  defp handle_import_form_params(socket, _params) do
    assign(socket, import: nil)
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"book" => book_params}, socket) do
    changeset =
      socket.assigns.book
      |> Books.change_book(book_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"book" => book_params}, socket) do
    with {:ok, _book} <-
           socket.assigns.book
           |> Books.change_book(book_params)
           |> Changeset.apply_action(:insert) do
      save_book(socket, socket.assigns.live_action, book_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("open-import-form", %{"type" => type}, socket) do
    query = socket.assigns.form.params["title"] || socket.assigns.book.title
    import_type = String.to_existing_atom(type)
    socket = assign(socket, import: %{type: import_type, query: query})

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"book" => book_params}}, socket) do
    # authors and/or series could have been created, reload the data-lists
    socket =
      assign(socket,
        authors: People.authors_for_select(),
        series: Books.series_for_select()
      )

    new_params = Map.merge(socket.assigns.form.params, book_params)
    changeset = Books.change_book(socket.assigns.book, new_params)

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  defp save_book(socket, :edit, book_params) do
    case Books.update_book(socket.assigns.book, book_params) do
      {:ok, book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{book.title}")
         |> push_navigate(to: ~p"/admin/books")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_book(socket, :new, book_params) do
    case Books.create_book(book_params) do
      {:ok, book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{book.title}")
         |> push_navigate(to: ~p"/admin/books")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp import_form(:goodreads), do: GoodreadsImportForm
  defp import_form(:audible), do: AudibleImportForm

  defp open_import_form(%Book{id: nil}, type), do: JS.patch(~p"/admin/books/new?import=#{type}")

  defp open_import_form(book, type), do: JS.patch(~p"/admin/books/#{book}/edit?import=#{type}")

  defp close_import_form(%Book{id: nil}), do: JS.patch(~p"/admin/books/new", replace: true)
  defp close_import_form(book), do: JS.patch(~p"/admin/books/#{book}/edit", replace: true)

  defp preview_date_format(form) do
    format_published(%{
      published_format: Ecto.Changeset.get_field(form.source, :published_format),
      published: Ecto.Changeset.get_field(form.source, :published)
    })
  end
end
