defmodule AmbryWeb.Admin.PersonLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.Admin.{Components, UploadHelpers}
  import AmbryWeb.Admin.ParamHelpers, only: [map_to_list: 2]

  alias Ambry.People

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket = allow_image_upload(socket)
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(%{person: person} = assigns, socket) do
    changeset = People.change_person(person, init_person_param(person))

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"person" => person_params}, socket) do
    person_params = clean_person_params(person_params)

    changeset =
      socket.assigns.person
      |> People.change_person(person_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"person" => person_params}, socket) do
    person_params =
      case consume_uploaded_image(socket) do
        {:ok, :no_file} -> person_params
        {:ok, path} -> Map.put(person_params, "image_path", path)
        {:error, :too_many_files} -> raise "too many files"
      end

    save_person(socket, socket.assigns.action, person_params)
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("add-author", _params, socket) do
    params =
      socket.assigns.form.source.params
      |> map_to_list("authors")
      |> Map.update!("authors", fn authors_params ->
        authors_params ++ [%{}]
      end)

    changeset = People.change_person(socket.assigns.person, params)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("add-narrator", _params, socket) do
    params =
      socket.assigns.form.source.params
      |> map_to_list("narrators")
      |> Map.update!("narrators", fn narrators_params ->
        narrators_params ++ [%{}]
      end)

    changeset = People.change_person(socket.assigns.person, params)

    {:noreply, assign_form(socket, changeset)}
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
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_person(socket, :new, person_params) do
    case People.create_person(person_params) do
      {:ok, _person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Person created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp init_person_param(person) do
    %{
      "authors" => Enum.map(person.authors, &%{"id" => &1.id}),
      "narrators" => Enum.map(person.narrators, &%{"id" => &1.id})
    }
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
