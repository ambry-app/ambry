defmodule AmbryWeb.Admin.LocationLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Library
  alias Ambry.Library.Root
  alias Ambry.Library.Source
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new_source, _params) do
    source = %Source{import_policy: :hardlink}

    socket
    |> assign(page_title: "New Source", entity: source)
    |> assign_source_form(Library.change_source(source))
  end

  defp apply_action(socket, :edit_source, %{"id" => id}) do
    source = Library.get_source!(id)

    socket
    |> assign(page_title: source.name, entity: source)
    |> assign_source_form(Library.change_source(source))
  end

  defp apply_action(socket, :new_root, _params) do
    root = %Root{}

    socket
    |> assign(page_title: "New Library Root", entity: root)
    |> assign_root_form(Library.change_root(root))
  end

  defp apply_action(socket, :edit_root, %{"id" => id}) do
    root = Library.get_root!(id)

    socket
    |> assign(page_title: root.name, entity: root)
    |> assign_root_form(Library.change_root(root))
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"source" => params}, socket) do
    changeset =
      socket.assigns.entity
      |> Library.change_source(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_source_form(socket, changeset)}
  end

  def handle_event("validate", %{"root" => params}, socket) do
    changeset =
      socket.assigns.entity
      |> Library.change_root(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_root_form(socket, changeset)}
  end

  def handle_event("submit", %{"source" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new_source -> Library.create_source(params)
        :edit_source -> Library.update_source(socket.assigns.entity, params)
      end

    saved(result, socket, &assign_source_form/2)
  end

  def handle_event("submit", %{"root" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new_root -> Library.create_root(params)
        :edit_root -> Library.update_root(socket.assigns.entity, params)
      end

    saved(result, socket, &assign_root_form/2)
  end

  defp saved(result, socket, assign_form) do
    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved #{saved.name}")
         |> push_navigate(to: ~p"/admin/locations")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form.(socket, changeset)}
    end
  end

  defp assign_source_form(socket, %Changeset{} = changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:type, :source)
    |> assign(:status, path_status(Changeset.get_field(changeset, :path)))
    |> assign(:root_options, root_options())
  end

  defp assign_root_form(socket, %Changeset{} = changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:type, :root)
    |> assign(:status, path_status(Changeset.get_field(changeset, :path)))
    |> assign(:root_options, [])
  end

  defp root_options do
    Enum.map(Library.list_roots(), &{&1.name, &1.id})
  end

  defp root_prompt([]), do: "No library roots yet"
  defp root_prompt([{name, _id}]), do: "#{name} (the only root)"
  defp root_prompt(_several), do: "Choose a library root"

  # Checking the path as it's typed is worth the stat call: "that folder isn't
  # there" is the single most common way one of these rows is wrong, and
  # finding out at save time (or worse, at scan time) is far too late.
  defp path_status(path) when is_binary(path) and path != "" do
    if Path.type(path) == :absolute, do: Library.status(path)
  end

  defp path_status(_blank), do: nil

  # The one question a source answers, asked in the operator's terms: what
  # import does with these files. The old durability question ("can they be
  # trusted to stay?") is answered by the choice — symlink if they'll stay,
  # anything else if they might not.
  defp policy_options do
    [
      {"Hardlink (same filesystem only, no extra storage)", :hardlink},
      {"Symlink (crosses filesystems; dangles if the source ever moves)", :symlink},
      {"Copy (duplicates the files)", :copy},
      {"Move (empties the source folder)", :move}
    ]
  end
end
