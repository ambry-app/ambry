defmodule AmbryWeb.Admin.LocationLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Library
  alias Ambry.Library.Location
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    location = Library.get_location!(id)

    socket
    |> assign(page_title: location.name, location: location)
    |> assign_form(Library.change_location(location))
  end

  defp apply_action(socket, :new, _params) do
    location = %Location{kind: :downloads, import_policy: :hardlink}

    socket
    |> assign(page_title: "New Location", location: location)
    |> assign_form(Library.change_location(location))
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"location" => location_params}, socket) do
    changeset =
      socket.assigns.location
      |> Library.change_location(location_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"location" => location_params}, socket) do
    save_location(socket, socket.assigns.live_action, location_params)
  end

  defp save_location(socket, :edit, location_params) do
    case Library.update_location(socket.assigns.location, location_params) do
      {:ok, location} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{location.name}")
         |> push_navigate(to: ~p"/admin/locations")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_location(socket, :new, location_params) do
    case Library.create_location(location_params) do
      {:ok, location} ->
        {:noreply,
         socket
         |> put_flash(:info, "Added #{location.name}")
         |> push_navigate(to: ~p"/admin/locations")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:kind, Changeset.get_field(changeset, :kind))
    |> assign(:status, path_status(Changeset.get_field(changeset, :path)))
    |> assign(:root_options, root_options())
  end

  # Only roots can receive imports, so only roots are offered.
  defp root_options do
    Enum.map(Library.library_roots(), &{&1.name, &1.id})
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

  defp kind_options do
    [
      {"Downloads — messy source, imported into a library root", :downloads},
      {"External collection — organized elsewhere, adopted in place", :external_collection},
      {"Library root — Ambry's own tree", :library_root}
    ]
  end

  defp policy_options do
    [
      {"Hardlink — same filesystem only, costs no extra storage", :hardlink},
      {"Copy — duplicates the files", :copy},
      {"Move — leaves the source folder empty", :move}
    ]
  end
end
