defmodule AmbryWeb.Admin.BookLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.Admin.ParamHelpers, only: [map_to_list: 2]
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.{Authors, Books}

  alias Surface.Components.{Form, LiveFileInput}

  alias Surface.Components.Form.{
    Checkbox,
    DateInput,
    ErrorTag,
    Field,
    HiddenInputs,
    Inputs,
    Label,
    Select,
    Submit,
    TextArea,
    TextInput
  }

  prop title, :string, required: true
  prop book, :any, required: true
  prop action, :atom, required: true
  prop return_to, :string, required: true

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket = allow_image_upload(socket)
    {:ok, assign(socket, :authors, authors())}
  end

  @impl Phoenix.LiveComponent
  def update(%{book: book} = assigns, socket) do
    changeset = Books.change_book(book, init_book_param(book))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"book" => book_params}, socket) do
    book_params = clean_book_params(book_params)

    changeset =
      socket.assigns.book
      |> Books.change_book(book_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"book" => book_params}, socket) do
    book_params =
      case consume_uploaded_image(socket) do
        {:ok, :no_file} -> book_params
        {:ok, path} -> Map.put(book_params, "image_path", path)
        {:error, :too_many_files} -> raise "too many files"
      end

    save_book(socket, socket.assigns.action, book_params)
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("add-author", _params, socket) do
    params =
      socket.assigns.changeset.params
      |> map_to_list("book_authors")
      |> Map.update!("book_authors", fn book_authors_params ->
        book_authors_params ++ [%{}]
      end)

    changeset = Books.change_book(socket.assigns.book, params)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp clean_book_params(params) do
    params
    |> map_to_list("book_authors")
    |> Map.update!("book_authors", fn book_authors ->
      Enum.reject(book_authors, fn book_author_params ->
        is_nil(book_author_params["id"]) && book_author_params["delete"] == "true"
      end)
    end)
  end

  defp save_book(socket, :edit, book_params) do
    case Books.update_book(socket.assigns.book, book_params) do
      {:ok, _book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Book updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_book(socket, :new, book_params) do
    case Books.create_book(book_params) do
      {:ok, _book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Book created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp authors do
    Authors.for_select()
  end

  defp init_book_param(book) do
    %{
      "book_authors" => Enum.map(book.book_authors, &%{"id" => &1.id})
    }
  end
end
