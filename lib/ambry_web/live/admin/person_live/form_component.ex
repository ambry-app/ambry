defmodule AmbryWeb.Admin.PersonLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import Ambry.Paths

  alias Ambry.People

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

  prop title, :string, required: true
  prop person, :any, required: true
  prop action, :atom, required: true
  prop return_to, :string, required: true

  @impl true
  def mount(socket) do
    socket = allow_upload(socket, :image, accept: ~w(.jpg .jpeg .png), max_entries: 1)
    {:ok, socket}
  end

  @impl true
  def update(%{person: person} = assigns, socket) do
    changeset = People.change_person(person, init_person_param(person))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"person" => person_params}, socket) do
    person_params = clean_person_params(person_params)

    changeset =
      socket.assigns.person
      |> People.change_person(person_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"person" => person_params}, socket) do
    folder = Path.join([uploads_path(), "images"])
    File.mkdir_p!(folder)

    uploaded_files =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        data = File.read!(path)
        hash = :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
        [ext | _] = MIME.extensions(entry.client_type)
        filename = "#{hash}.#{ext}"
        dest = Path.join([folder, filename])
        File.cp!(path, dest)
        Routes.static_path(socket, "/uploads/images/#{filename}")
      end)

    person_params =
      case uploaded_files do
        [file] -> Map.put(person_params, "image_path", file)
        [] -> person_params
        _else -> raise "too many files"
      end

    save_person(socket, socket.assigns.action, person_params)
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

    changeset = People.change_person(socket.assigns.person, params)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("add-narrator", _params, socket) do
    params =
      socket.assigns.changeset.params
      |> map_to_list("narrators")
      |> Map.update!("narrators", fn narrators_params ->
        narrators_params ++ [%{}]
      end)

    changeset = People.change_person(socket.assigns.person, params)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp clean_person_params(params) do
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

  defp save_person(socket, :edit, person_params) do
    case People.update_person(socket.assigns.person, person_params) do
      {:ok, _person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Person updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_person(socket, :new, person_params) do
    case People.create_person(person_params) do
      {:ok, _person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Person created successfully")
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

  defp init_person_param(person) do
    %{
      "authors" => Enum.map(person.authors, &%{"id" => &1.id}),
      "narrators" => Enum.map(person.narrators, &%{"id" => &1.id})
    }
  end
end
