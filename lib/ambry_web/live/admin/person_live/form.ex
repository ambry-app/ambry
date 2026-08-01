defmodule AmbryWeb.Admin.PersonLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Metadata.Registry
  alias Ambry.People
  alias Ambry.People.Author
  alias Ambry.People.Person
  alias AmbryWeb.Admin.PersonLive.Form.ImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> assign(
       import: nil,
       providers: Registry.enabled(capability: :author_search),
       authors: People.authors_for_select()
     )
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

  defp handle_import_form_params(socket, %{"import" => provider_id}) do
    query = socket.assigns.form.params["name"] || socket.assigns.person.name

    case Registry.fetch(provider_id) do
      {:ok, provider} -> assign(socket, import: %{provider: provider, query: query})
      {:error, :unknown_provider} -> assign(socket, import: nil)
    end
  end

  defp handle_import_form_params(socket, _params) do
    assign(socket, import: nil)
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"person" => person_params}, socket) do
    person_params = maybe_link_author(person_params)

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
    person_params = maybe_link_author(person_params)

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

  def handle_event("open-import-form", %{"type" => provider_id}, socket) do
    {:noreply, handle_import_form_params(socket, %{"import" => provider_id})}
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

  # Selecting an author in the "link an existing author" autocomplete stages an
  # `author_people` row linking that author (unless it's already present).
  defp maybe_link_author(%{"link_author_id" => id} = person_params) when id not in [nil, ""] do
    author_people = person_params["author_people"] || %{}

    linked_ids =
      author_people
      |> Map.values()
      |> Enum.flat_map(&[&1["author_id"], get_in(&1, ["author", "id"])])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    person_params = Map.put(person_params, "link_author_id", "")

    if to_string(id) in linked_ids do
      person_params
    else
      next_index =
        author_people
        |> Map.keys()
        |> Enum.map(&String.to_integer/1)
        |> Enum.max(fn -> -1 end)
        |> Kernel.+(1)
        |> to_string()

      sort = person_params["author_people_sort"] || []

      person_params
      |> Map.put("author_people", Map.put(author_people, next_index, %{"author_id" => id}))
      |> Map.put("author_people_sort", sort ++ [next_index])
    end
  end

  defp maybe_link_author(person_params), do: person_params

  defp linked_author_row?(author_person_form) do
    is_nil(author_person_form.data.id) and
      author_person_form[:author_id].value not in [nil, ""]
  end

  defp linked_author_name(authors, value) do
    Enum.find_value(authors, fn {name, id} -> to_string(id) == to_string(value) && name end)
  end

  defp shared_with(author_person_form, person) do
    case author_person_form.data.author do
      %Author{people: people} when is_list(people) ->
        people
        |> Enum.reject(&(&1.id == person.id))
        |> Enum.map(& &1.name)

      _author ->
        []
    end
  end

  defp open_import_form(%Person{id: nil}, type),
    do: JS.patch(~p"/admin/people/new?import=#{type}")

  defp open_import_form(person, type),
    do: JS.patch(~p"/admin/people/#{person}/edit?import=#{type}")

  defp close_import_form(%Person{id: nil}), do: JS.patch(~p"/admin/people/new", replace: true)
  defp close_import_form(person), do: JS.patch(~p"/admin/people/#{person}/edit", replace: true)
end
