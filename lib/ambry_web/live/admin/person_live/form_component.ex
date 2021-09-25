defmodule AmbryWeb.Admin.PersonLive.FormComponent do
  use AmbryWeb, :live_component

  alias Ambry.People

  alias Surface.Components.{Form, LiveFileInput}

  alias Surface.Components.Form.{
    ErrorTag,
    Field,
    Label,
    Submit,
    TextArea,
    TextInput
  }

  @uploads_path Application.compile_env!(:ambry, :uploads_path)

  prop title, :string, required: true
  prop person, :any, required: true
  prop action, :atom, required: true
  prop return_to, :string, required: true

  def mount(socket) do
    socket = allow_upload(socket, :image, accept: ~w(.jpg .jpeg .png), max_entries: 1)
    {:ok, socket}
  end

  @impl true
  def update(%{person: person} = assigns, socket) do
    changeset = People.change_person(person)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"person" => person_params}, socket) do
    changeset =
      socket.assigns.person
      |> People.change_person(person_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"person" => person_params}, socket) do
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
end
