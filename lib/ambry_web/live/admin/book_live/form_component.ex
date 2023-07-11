defmodule AmbryWeb.Admin.BookLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.ParamHelpers, only: [map_to_list: 2]
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Authors
  alias Ambry.Books
  alias Ambry.Series
  alias AmbryScraping.Audible
  alias AmbryScraping.Audnexus
  alias AmbryScraping.HTMLToMD

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket = allow_image_upload(socket, :image)

    {:ok,
     socket
     |> assign(:authors, authors())
     |> assign(:series, series())}
  end

  @impl Phoenix.LiveComponent
  def update(%{book: book} = assigns, socket) do
    changeset = Books.change_book(book, init_book_param(book))

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)
     |> assign_audnexus_form()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"book" => book_params}, socket) do
    book_params = clean_book_params(book_params)

    changeset =
      socket.assigns.book
      |> Books.change_book(book_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("add-author", _params, socket) do
    params =
      socket.assigns.form.source.params
      |> map_to_list("book_authors")
      |> Map.update!("book_authors", fn book_authors_params ->
        book_authors_params ++ [%{}]
      end)

    changeset = Books.change_book(socket.assigns.book, params)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("add-series", _params, socket) do
    params =
      socket.assigns.form.source.params
      |> map_to_list("series_books")
      |> Map.update!("series_books", fn series_books_params ->
        series_books_params ++ [%{}]
      end)

    changeset = Books.change_book(socket.assigns.book, params)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("import-book", params, socket) do
    case params do
      %{"asin" => "", "title" => ""} -> {:noreply, socket}
      %{"asin" => "", "title" => title} -> import_from_title(title, socket)
      %{"asin" => asin} -> import_from_asin(asin, socket)
    end
  end

  def handle_event("save", %{"book" => book_params}, socket) do
    with {:ok, book_params} <- handle_upload(socket, book_params, :image),
         {:ok, book_params} <- handle_import(book_params["image_import_url"], book_params) do
      save_book(socket, socket.assigns.action, book_params)
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def import_from_asin(asin, socket) do
    case Audnexus.Book.get(asin) do
      {:ok, book_details} ->
        changeset = audnexus_book_changeset(socket.assigns.book, book_details)
        {:noreply, socket |> assign_form(changeset) |> assign_audnexus_form(%{"asin" => asin})}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Error getting results from Audnexus")}
    end
  end

  def import_from_title(title, socket) do
    with {:ok, asin} <- Audible.Product.search(title),
         {:ok, book_details} <- Audnexus.Book.get(asin) do
      changeset = audnexus_book_changeset(socket.assigns.book, book_details)
      {:noreply, socket |> assign_form(changeset) |> assign_audnexus_form(%{"title" => title})}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Error getting results from Audnexus")}
    end
  end

  defp handle_upload(socket, book_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, book_params}
      {:ok, path} -> {:ok, Map.put(book_params, "image_path", path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_import(url, book_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, book_params}
      {:ok, path} -> {:ok, Map.put(book_params, "image_path", path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp audnexus_book_changeset(book, audnexus_book_details) do
    params =
      book
      |> init_book_param()
      |> Map.merge(%{
        "title" => audnexus_book_details["title"],
        "description" => HTMLToMD.html_to_md(audnexus_book_details["summary"]),
        "image_import_url" => audnexus_book_details["image"]
      })
      |> Map.update!("book_authors", &audnexus_book_authors_params(&1, audnexus_book_details))
      |> Map.update!("series_books", &audnexus_series_books_params(&1, audnexus_book_details))

    Books.change_book(book, params)
  end

  defp audnexus_book_authors_params([], audnexus_book_details) do
    matching_authors = audnexus_matching_authors(audnexus_book_details)

    Enum.flat_map(audnexus_book_details["authors"], fn %{"name" => name} ->
      case matching_authors[name] do
        %Authors.Author{} = author -> [%{"author_id" => author.id}]
        nil -> []
      end
    end)
  end

  defp audnexus_book_authors_params(existing_authors, _audnexus_book_details), do: existing_authors

  defp audnexus_series_books_params([], audnexus_book_details) do
    audnexus_book_details |> audnexus_series_book_params() |> List.wrap()
  end

  defp audnexus_series_books_params(existing_series_books, _audnexus_book_details), do: existing_series_books

  defp audnexus_matching_authors(book_details) do
    book_details["authors"]
    |> Enum.map(& &1["name"])
    |> Ambry.Authors.find_by_names()
  end

  defp audnexus_series_book_params(%{"seriesPrimary" => %{"name" => name, "position" => position}}) do
    case Ambry.Series.find_by_name(name) do
      {:ok, series} ->
        %{"series_id" => series.id, "book_number" => position}

      _term ->
        nil
    end
  end

  defp audnexus_series_book_params(_book_details), do: nil

  defp clean_book_params(params) do
    params
    |> map_to_list("book_authors")
    |> Map.update!("book_authors", fn book_authors ->
      Enum.reject(book_authors, fn book_author_params ->
        is_nil(book_author_params["id"]) && book_author_params["delete"] == "true"
      end)
    end)
    |> map_to_list("series_books")
    |> Map.update!("series_books", fn series_books ->
      Enum.reject(series_books, fn series_book_params ->
        is_nil(series_book_params["id"]) && series_book_params["delete"] == "true"
      end)
    end)
  end

  defp save_book(socket, :edit, book_params) do
    case Books.update_book(socket.assigns.book, book_params) do
      {:ok, _book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Book updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_book(socket, :new, book_params) do
    case Books.create_book(book_params) do
      {:ok, _book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Book created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp authors do
    Authors.for_select()
  end

  defp series do
    Series.for_select()
  end

  defp init_book_param(book) do
    %{
      "book_authors" => Enum.map(book.book_authors, &%{"id" => &1.id}),
      "series_books" => Enum.map(book.series_books, &%{"id" => &1.id})
    }
  end

  defp toggle_import do
    %JS{}
    |> JS.toggle(to: "#toggle-import-link")
    |> JS.toggle(to: "#import-form")
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_audnexus_form(socket, params \\ %{}) do
    assign(socket, :audnexus_form, to_form(params))
  end
end
