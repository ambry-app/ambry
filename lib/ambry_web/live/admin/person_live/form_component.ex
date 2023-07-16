defmodule AmbryWeb.Admin.PersonLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.ParamHelpers, only: [map_to_list: 2]
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.People
  alias Phoenix.LiveView.JS

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket = allow_image_upload(socket, :image)
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(%{person: person} = assigns, socket) do
    changeset = People.change_person(person, init_person_param(person))

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)
     |> assign_audnexus_form()}
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

  def handle_event("import-author", %{"query" => ""}, socket), do: {:noreply, socket}

  def handle_event("import-author", %{"query" => query}, socket) do
    with {:ok, [%{"asin" => asin} | _rest]} <- Audnexus.Author.search(query),
         {:ok, author_details} <- Audnexus.Author.get(asin) do
      changeset = audnexus_person_changeset(socket.assigns.person, author_details)

      {:noreply, socket |> assign_form(changeset) |> assign_audnexus_form(query)}
    else
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "No authors found by that name")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Error getting results from Audnexus")}
    end
  end

  def handle_event("save", %{"person" => person_params}, socket) do
    with {:ok, person_params} <- handle_upload(socket, person_params, :image),
         {:ok, person_params} <- handle_import(person_params["image_import_url"], person_params) do
      save_person(socket, socket.assigns.action, person_params)
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  defp handle_upload(socket, person_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, person_params}
      {:ok, path} -> {:ok, Map.put(person_params, "image_path", path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_import(url, person_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, person_params}
      {:ok, path} -> {:ok, Map.put(person_params, "image_path", path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp audnexus_person_changeset(person, author_details) do
    params =
      person
      |> init_person_param()
      |> Map.merge(%{
        "name" => author_details["name"],
        "description" => author_details["description"],
        "image_import_url" => author_details["image"]
      })
      |> Map.update!("authors", fn
        [] -> [%{"name" => author_details["name"]}]
        authors -> authors
      end)

    People.change_person(person, params)
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

  defp toggle_import do
    %JS{}
    |> JS.toggle(to: "#toggle-import-link")
    |> JS.toggle(to: "#import-form")
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_audnexus_form(socket, query \\ "") do
    assign(socket, :audnexus_form, to_form(%{"query" => query}))
  end
end
