defmodule AmbryWeb.Admin.PersonLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Metadata.Audible
  alias Ambry.Metadata.GoodReads
  alias Ambry.People
  alias Ambry.People.Person

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> allow_image_upload(:image)
      |> assign(import: nil)

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    person = People.get_person!(id)
    changeset = People.change_person(person, %{})

    socket
    |> assign(
      page_title: person.name,
      header_title: person.name,
      person: person
    )
    |> assign_form(changeset)
  end

  defp apply_action(socket, :new, _params) do
    person = %Person{}
    changeset = People.change_person(person, %{"image_type" => "upload"})

    socket
    |> assign(
      page_title: "New Person",
      header_title: "New Person",
      person: person
    )
    |> assign_form(changeset)
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"person" => person_params}, socket) do
    socket =
      if person_params["image_type"] != "upload" do
        cancel_all_uploads(socket, :image)
      else
        socket
      end

    changeset =
      socket.assigns.person
      |> People.change_person(person_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"import" => import_type, "person" => person_params}, socket) do
    changeset =
      socket.assigns.person
      |> People.change_person(person_params)
      |> Map.put(:action, :validate)

    if Keyword.has_key?(changeset.errors, :name) do
      {:noreply, assign_form(socket, changeset)}
    else
      socket = async_import_search(socket, String.to_existing_atom(import_type), person_params["name"])
      {:noreply, socket}
    end
  end

  def handle_event("submit", %{"person" => person_params}, socket) do
    with {:ok, _person} <-
           socket.assigns.person |> People.change_person(person_params) |> Ecto.Changeset.apply_action(:insert),
         {:ok, person_params} <- handle_upload(socket, person_params, :image),
         {:ok, person_params} <- handle_import(person_params["image_import_url"], person_params) do
      save_person(socket, socket.assigns.live_action, person_params)
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("import-search", %{"import_search" => %{"query" => query}}, socket) do
    socket = async_import_search(socket, socket.assigns.import.type, query)
    {:noreply, socket}
  end

  def handle_event("import-details", %{"import_details" => %{"author_id" => author_id}}, socket) do
    socket = async_import_details(socket, socket.assigns.import.type, author_id)
    {:noreply, socket}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    author = socket.assigns.import.details
    existing_params = socket.assigns.form.params

    new_params =
      Enum.reduce(import_params, existing_params, fn
        {"use_name", "true"}, acc ->
          Map.put(acc, "name", author.name)

        {"use_description", "true"}, acc ->
          Map.put(acc, "description", author.description)

        {"use_image", "true"}, acc ->
          Map.merge(acc, %{"image_type" => "url_import", "image_import_url" => author.image.src})

        _else, acc ->
          acc
      end)

    changeset = People.change_person(socket.assigns.person, new_params)

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  def handle_event("cancel-import", _params, socket) do
    {:noreply, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_info({_tas_ref, {import_type, :search, {:ok, results}}}, socket) do
    socket =
      update(socket, :import, fn import_assigns ->
        %{import_assigns | search_loading: false, results: results}
      end)

    socket =
      case results do
        [] ->
          socket

        [first_result | _rest] ->
          async_import_details(socket, import_type, first_result.id)
      end

    {:noreply, socket}
  end

  def handle_info({_tas_ref, {_import_type, :search, {:error, _reason}}}, socket) do
    socket =
      socket
      |> update(:import, fn import_assigns ->
        %{import_assigns | search_loading: false}
      end)
      |> put_flash(:error, "search failed")

    {:noreply, socket}
  end

  def handle_info({_tas_ref, {_import_type, :details, {:ok, result}}}, socket) do
    socket =
      update(socket, :import, fn import_assigns ->
        %{import_assigns | details_loading: false, details: result}
      end)

    {:noreply, socket}
  end

  def handle_info({_tas_ref, {_import_type, :details, {:error, _reason}}}, socket) do
    socket =
      socket
      |> update(:import, fn import_assigns ->
        %{import_assigns | details_loading: false}
      end)
      |> put_flash(:error, "fetch failed")

    {:noreply, socket}
  end

  def handle_info({:DOWN, _task_ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  defp cancel_all_uploads(socket, upload) do
    Enum.reduce(socket.assigns.uploads[upload].entries, socket, fn entry, socket ->
      cancel_upload(socket, upload, entry.ref)
    end)
  end

  defp handle_upload(socket, person_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, person_params}
      {:ok, path} -> {:ok, Map.put(person_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_upload}
    end
  end

  defp handle_import(url, person_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, person_params}
      {:ok, path} -> {:ok, Map.put(person_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_import}
    end
  end

  defp save_person(socket, :edit, person_params) do
    case People.update_person(socket.assigns.person, person_params) do
      {:ok, person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{person.name}")
         |> push_navigate(to: ~p"/admin/people")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_person(socket, :new, person_params) do
    case People.create_person(person_params) do
      {:ok, person} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{person.name}")
         |> push_navigate(to: ~p"/admin/people")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp async_import_search(socket, :goodreads, query),
    do: do_async_import_search(socket, :goodreads, query, &GoodReads.search_authors/1)

  defp async_import_search(socket, :audible, query),
    do: do_async_import_search(socket, :audible, query, &Audible.search_authors/1)

  defp do_async_import_search(socket, import_type, query, query_fun) do
    Task.async(fn ->
      response = query_fun.(query |> String.trim() |> String.downcase())
      {import_type, :search, response}
    end)

    assign(socket,
      import: %{
        type: import_type,
        search_form: to_form(%{"query" => query}, as: :import_search),
        search_loading: true,
        results: nil,
        details_form: to_form(%{}, as: :import_details),
        details_loading: false,
        details: nil,
        form: to_form(init_import_form_params(socket.assigns.person), as: :import)
      }
    )
  end

  defp async_import_details(socket, :goodreads, author_id),
    do: do_async_import_details(socket, :goodreads, author_id, &GoodReads.author/1)

  defp async_import_details(socket, :audible, author_id),
    do: do_async_import_details(socket, :audible, author_id, &Audible.author/1)

  defp do_async_import_details(socket, import_type, author_id, details_fun) do
    Task.async(fn ->
      response = details_fun.(author_id)
      {import_type, :details, response}
    end)

    update(socket, :import, fn import_assigns ->
      %{
        import_assigns
        | details_form: to_form(%{"author_id" => author_id}, as: :import_details),
          details_loading: true,
          details: nil
      }
    end)
  end

  defp init_import_form_params(person) do
    Map.new([:name, :description, :image], fn
      :name -> {"use_name", is_nil(person.name)}
      :description -> {"use_description", is_nil(person.description)}
      :image -> {"use_image", is_nil(person.image_path)}
    end)
  end
end
