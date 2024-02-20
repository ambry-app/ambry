defmodule AmbryWeb.Admin.BookLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Books
  alias Ambry.Books.Book
  alias AmbryWeb.Admin.BookLive.Form.AudibleImportForm
  alias AmbryWeb.Admin.BookLive.Form.GoodreadsImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> assign(
       import: nil,
       scraping_available: AmbryScraping.web_scraping_available?(),
       authors: Ambry.Authors.for_select(),
       series: Ambry.Series.for_select()
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    book = Books.get_book!(id)
    init_params = if book.image_path, do: %{}, else: %{"image_type" => "upload"}
    changeset = Books.change_book(book, init_params)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: book.title,
      book: book
    )
  end

  defp apply_action(socket, :new, _params) do
    book = %Book{book_authors: [], series_books: []}
    changeset = Books.change_book(book, %{"image_type" => "upload"})

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Book",
      book: book
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"book" => book_params}, socket) do
    socket =
      if book_params["image_type"] != "upload" do
        cancel_all_uploads(socket, :image)
      else
        socket
      end

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
           |> Changeset.apply_action(:insert),
         {:ok, book_params} <- handle_image_upload(socket, book_params, :image),
         {:ok, book_params} <- handle_image_import(book_params["image_import_url"], book_params) do
      save_book(socket, socket.assigns.live_action, book_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def handle_event("open-import-form", %{"type" => type}, socket) do
    query = socket.assigns.form.params["title"]
    import_type = String.to_existing_atom(type)
    socket = assign(socket, import: %{type: import_type, query: query})

    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("cancel-import", _params, socket) do
    {:noreply, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"book" => book_params}}, socket) do
    # authors and/or series could have been created, reload the data-lists
    socket =
      assign(socket,
        authors: Ambry.Authors.for_select(),
        series: Ambry.Series.for_select()
      )

    new_params = Map.merge(socket.assigns.form.params, book_params)
    changeset = Books.change_book(socket.assigns.book, new_params)

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  defp cancel_all_uploads(socket, upload) do
    Enum.reduce(socket.assigns.uploads[upload].entries, socket, fn entry, socket ->
      cancel_upload(socket, upload, entry.ref)
    end)
  end

  defp handle_image_upload(socket, book_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, book_params}
      {:ok, path} -> {:ok, Map.put(book_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_upload}
    end
  end

  defp handle_image_import(url, book_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, book_params}
      {:ok, path} -> {:ok, Map.put(book_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_import}
    end
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

  defp open_import_form(type), do: JS.push("open-import-form", value: %{"type" => type})
end
