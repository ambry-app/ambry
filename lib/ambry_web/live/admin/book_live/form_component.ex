defmodule AmbryWeb.Admin.BookLive.FormComponent do
  use AmbryWeb, :live_component

  alias Ambry.Books

  alias Surface.Components.{Form, LiveFileInput}

  alias Surface.Components.Form.{
    Checkbox,
    ErrorTag,
    Field,
    HiddenInputs,
    Inputs,
    Label,
    Submit,
    TextArea,
    TextInput
  }

  @uploads_path Application.compile_env!(:ambry, :uploads_path)

  prop title, :string, required: true
  prop book, :any, required: true
  prop action, :atom, required: true
  prop return_to, :string, required: true

  def mount(socket) do
    socket = allow_upload(socket, :image, accept: ~w(.jpg .jpeg .png), max_entries: 1)
    {:ok, socket}
  end

  @impl true
  def update(%{book: book} = assigns, socket) do
    changeset = Books.change_book(book, init_book_param(book))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"book" => book_params}, socket) do
    book_params = clean_book_params(book_params)

    changeset =
      socket.assigns.book
      |> Books.change_book(book_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"book" => book_params}, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        data = File.read!(path)
        hash = :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
        [ext | _] = MIME.extensions(entry.client_type)
        filename = "#{hash}.#{ext}"
        dest = Path.join([@uploads_path, "images", filename])
        File.cp!(path, dest)
        Routes.static_path(socket, "/uploads/images/#{filename}")
      end)

    book_params =
      case uploaded_files do
        [file] -> Map.put(book_params, "image_path", file)
        [] -> book_params
        _else -> raise "too many files"
      end

    save_book(socket, socket.assigns.action, book_params)
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("add-author", _params, socket) do
    params =
      socket.assigns.changeset.params
      |> map_to_list("authors")
      |> Map.update!("authors", fn authors_params ->
        authors_params ++ [%{}]
      end)

    changeset = Books.change_book(socket.assigns.book, params)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("add-narrator", _params, socket) do
    params =
      socket.assigns.changeset.params
      |> map_to_list("narrators")
      |> Map.update!("narrators", fn narrators_params ->
        narrators_params ++ [%{}]
      end)

    changeset = Books.change_book(socket.assigns.book, params)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp clean_book_params(params) do
    params
    |> map_to_list("authors")
    |> Map.update!("authors", fn authors ->
      Enum.reject(authors, fn author_params ->
        is_nil(author_params["id"]) && author_params["delete"] == "true"
      end)
    end)
    |> map_to_list("narrators")
    |> Map.update!("narrators", fn narrators ->
      Enum.reject(narrators, fn narrator_params ->
        is_nil(narrator_params["id"]) && narrator_params["delete"] == "true"
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

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:too_many_files), do: "You have selected too many files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp map_to_list(params, key) do
    if Map.has_key?(params, key) do
      Map.update!(params, key, fn
        params_map when is_map(params_map) ->
          params_map
          |> Enum.sort_by(fn {index, _params} -> String.to_integer(index) end)
          |> Enum.map(fn {_index, params} -> params end)

        params_list when is_list(params_list) ->
          params_list
      end)
    else
      Map.put(params, key, [])
    end
  end

  defp init_book_param(book) do
    %{
      "authors" => Enum.map(book.authors, &%{"id" => &1.id}),
      "narrators" => Enum.map(book.narrators, &%{"id" => &1.id})
    }
  end
end
