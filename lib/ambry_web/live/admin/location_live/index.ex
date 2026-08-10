defmodule AmbryWeb.Admin.LocationLive.Index do
  @moduledoc """
  Where the library lives on disk: source folders and library roots.

  The page leans on one thing the operator can't get anywhere else — which
  locations share a filesystem. Hardlinks can't cross one, so "these two are
  on the same disk" is the difference between an import costing nothing and
  an import doubling storage, and it's invisible from the paths alone.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Inbox
  alias Ambry.Library

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Locations") |> load_locations()}
  end

  @impl Phoenix.LiveView
  def handle_event("scan", _params, socket) do
    case Inbox.discover_async() do
      {:ok, _job} ->
        {:noreply,
         put_flash(socket, :info, "Scanning every enabled location. Check the inbox shortly.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't start a scan.")}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    location = Library.get_location!(id)
    {:ok, location} = Library.update_location(location, %{enabled: !location.enabled})

    {:noreply,
     socket
     |> put_flash(
       :info,
       "#{location.name} is now #{(location.enabled && "watched") || "paused"}."
     )
     |> load_locations()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    location = Library.get_location!(id)
    {:ok, _location} = Library.delete_location(location)

    {:noreply,
     socket
     |> put_flash(:info, "Removed #{location.name}. Its files were left alone.")
     |> load_locations()}
  end

  defp load_locations(socket) do
    locations = Library.list_locations()
    statuses = Map.new(locations, &{&1.id, Library.status(&1)})

    assign(socket,
      locations: locations,
      statuses: statuses,
      filesystems: label_filesystems(statuses)
    )
  end

  # Raw device numbers mean nothing to anyone, but "these two are on the same
  # one" means everything here, so distinct devices get short labels in the
  # order they're first seen.
  defp label_filesystems(statuses) do
    statuses
    |> Map.values()
    |> Enum.map(& &1.device)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new(fn {device, index} -> {device, <<?A + index>>} end)
  end

  defp kind_label(:downloads), do: "Downloads"
  defp kind_label(:external_collection), do: "External collection"
  defp kind_label(:library_root), do: "Library root"

  defp kind_blurb(:downloads),
    do: "Messy source. Imports are brought into a library root and become managed."

  defp kind_blurb(:external_collection),
    do: "Organized elsewhere. Imported items are adopted in place and never written to."

  defp kind_blurb(:library_root),
    do: "Ambry's own tree, organized by the naming template. Watched for hand-placed files."

  defp kind_class(:downloads), do: "bg-blue-950 text-blue-300"

  defp kind_class(:external_collection), do: "bg-amber-950 text-amber-300"

  defp kind_class(:library_root), do: "bg-lime-950 text-lime-300"

  defp policy_label(:hardlink), do: "hardlink"
  defp policy_label(:copy), do: "copy"
  defp policy_label(:move), do: "move"
  defp policy_label(nil), do: nil

  defp status_problem(status, kind) do
    cond do
      !status.exists? -> "Not found — is the volume mounted?"
      !status.directory? -> "Not a folder."
      kind != :external_collection and !status.writable? -> "Read-only, so nothing can land here."
      true -> nil
    end
  end

  defp scanned_label(nil), do: "never scanned"
  defp scanned_label(at), do: "scanned #{Calendar.strftime(at, "%x %X")}"
end
