defmodule AmbryWeb.Admin.LocationLive.Index do
  @moduledoc """
  Where the library physically lives: sources and library roots, as two
  sections because they are two concepts — sources are watched and read,
  roots are written and never watched.

  The page leans on one thing the operator can't get anywhere else — which
  paths share a filesystem. Hardlinks can't cross one, so "these two are on
  the same disk" is the difference between an import costing nothing and an
  import doubling storage, and it's invisible from the paths alone.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Inbox
  alias Ambry.Library

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Locations") |> load()}
  end

  @impl Phoenix.LiveView
  def handle_event("scan", _params, socket) do
    case Inbox.discover_async() do
      {:ok, _job} ->
        {:noreply,
         put_flash(socket, :info, "Scanning every watched source. Check the inbox shortly.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't start a scan.")}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    source = Library.get_source!(id)
    {:ok, source} = Library.update_source(source, %{enabled: !source.enabled})

    {:noreply,
     socket
     |> put_flash(:info, "#{source.name} is now #{(source.enabled && "watched") || "paused"}.")
     |> load()}
  end

  def handle_event("delete-source", %{"id" => id}, socket) do
    source = Library.get_source!(id)

    case Library.delete_source(source) do
      {:ok, _source} ->
        {:noreply,
         socket
         |> put_flash(:info, "Removed #{source.name}. Its files were left alone.")
         |> load()}

      {:error, {:referenced, %{inbox_items: items}}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{source.name} still has #{items} inbox item#{plural(items)} resolving through it. " <>
             "Import or remove them first."
         )}
    end
  end

  def handle_event("delete-root", %{"id" => id}, socket) do
    root = Library.get_root!(id)

    case Library.delete_root(root) do
      {:ok, _root} ->
        {:noreply,
         socket
         |> put_flash(:info, "Removed #{root.name}. Its files were left alone.")
         |> load()}

      {:error, {:referenced, %{media: media}}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{root.name} still holds #{media} recording#{plural(media)}. " <>
             "The library serves them from there, so the root has to outlive them."
         )}
    end
  end

  defp plural(1), do: ""
  defp plural(_many), do: "s"

  defp load(socket) do
    sources = Library.list_sources()
    roots = Library.list_roots()

    statuses =
      Map.new(
        Enum.map(sources, &{{:source, &1.id}, Library.status(&1)}) ++
          Enum.map(roots, &{{:root, &1.id}, Library.status(&1)})
      )

    assign(socket,
      sources: sources,
      roots: roots,
      statuses: statuses,
      filesystems: label_filesystems(statuses)
    )
  end

  # Raw device numbers mean nothing to anyone, but "these two can hardlink
  # between each other" means everything here, so each distinct
  # {device, mount} pair gets a short label in the order it's first seen.
  # Both halves, because that is what `link(2)` actually requires — see
  # `Ambry.Library.same_filesystem?/2`.
  defp label_filesystems(statuses) do
    statuses
    |> Map.values()
    |> Enum.reject(&is_nil(&1.device))
    |> Enum.map(&{&1.device, &1.mount})
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new(fn {key, index} -> {key, <<?A + index>>} end)
  end

  # The tag for one row, or nil for an unreachable path.
  defp filesystem_tag(_filesystems, %{device: nil}), do: nil
  defp filesystem_tag(filesystems, status), do: filesystems[{status.device, status.mount}]

  defp policy_label(:hardlink), do: "hardlink"
  defp policy_label(:symlink), do: "symlink"
  defp policy_label(:copy), do: "copy"
  defp policy_label(:move), do: "move"

  defp policy_blurb(:hardlink),
    do: "Import hardlinks its files into a root — one copy of the bytes, seeding untouched."

  defp policy_blurb(:symlink),
    do:
      "Import symlinks its files into a root. They're trusted to stay; the link dangles if they don't."

  defp policy_blurb(:copy), do: "Import copies its files into a root, duplicating the bytes."

  defp policy_blurb(:move), do: "Import moves its files into a root, leaving this folder clean."

  defp source_problem(status) do
    cond do
      !status.exists? -> "Not found. Is the volume mounted?"
      !status.directory? -> "Not a folder."
      true -> nil
    end
  end

  defp root_problem(status) do
    cond do
      !status.exists? -> "Not found. Is the volume mounted?"
      !status.directory? -> "Not a folder."
      !status.writable? -> "Read-only, so nothing can land here."
      true -> nil
    end
  end

  defp scanned_label(nil), do: "never scanned"
  defp scanned_label(at), do: "scanned #{Calendar.strftime(at, "%x %X")}"
end
