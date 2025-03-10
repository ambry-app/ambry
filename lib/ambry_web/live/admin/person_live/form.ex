defmodule AmbryWeb.Admin.PersonLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.People
  alias Ambry.People.Person
  alias AmbryWeb.Admin.PersonLive.Form.ImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> assign(import: nil, scraping_available: AmbryScraping.web_scraping_available?())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    person = People.get_person!(id)
    changeset = People.change_person(person, %{"image_type" => "upload"})

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: person.name,
      person: person
    )
  end

  defp apply_action(socket, :new, _params) do
    person = %Person{}
    changeset = People.change_person(person, %{"image_type" => "upload"})

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Author or Narrator",
      person: person
    )
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, handle_import_form_params(socket, params)}
  end

  defp handle_import_form_params(socket, %{"import" => type}) do
    query = socket.assigns.form.params["name"] || socket.assigns.person.name
    import_type = String.to_existing_atom(type)
    assign(socket, import: %{type: import_type, query: query})
  end

  defp handle_import_form_params(socket, _params) do
    assign(socket, import: nil)
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"person" => person_params}, socket) do
    socket =
      if person_params["image_type"] == "upload" do
        socket
      else
        cancel_all_uploads(socket, :image)
      end

    changeset =
      socket.assigns.person
      |> People.change_person(person_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"person" => person_params}, socket) do
    with {:ok, _person} <-
           socket.assigns.person
           |> People.change_person(person_params)
           |> Changeset.apply_action(:insert),
         {:ok, person_params} <- handle_image_upload(socket, person_params, :image),
         {:ok, person_params} <-
           handle_image_import(person_params["image_import_url"], person_params) do
      save_person(socket, socket.assigns.live_action, person_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def handle_event("open-import-form", %{"type" => type}, socket) do
    query = socket.assigns.form.params["name"] || socket.assigns.person.name
    import_type = String.to_existing_atom(type)
    socket = assign(socket, import: %{type: import_type, query: query})

    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"person" => person_params}}, socket) do
    new_params = Map.merge(socket.assigns.form.params, person_params)
    changeset = People.change_person(socket.assigns.person, new_params)
    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  defp cancel_all_uploads(socket, upload) do
    Enum.reduce(socket.assigns.uploads[upload].entries, socket, fn entry, socket ->
      cancel_upload(socket, upload, entry.ref)
    end)
  end

  defp handle_image_upload(socket, person_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, person_params}
      {:ok, path} -> {:ok, Map.put(person_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_upload}
    end
  end

  defp handle_image_import(url, person_params) do
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

      {:error, %Changeset{} = changeset} ->
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

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp open_import_form(%Person{id: nil}, type),
    do: JS.patch(~p"/admin/people/new?import=#{type}")

  defp open_import_form(person, type),
    do: JS.patch(~p"/admin/people/#{person}/edit?import=#{type}")

  defp close_import_form(%Person{id: nil}), do: JS.patch(~p"/admin/people/new", replace: true)
  defp close_import_form(person), do: JS.patch(~p"/admin/people/#{person}/edit", replace: true)
end
