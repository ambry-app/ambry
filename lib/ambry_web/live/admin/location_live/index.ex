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
    {:ok, _source} = Library.delete_source(source)

    {:noreply,
     socket
     |> put_flash(:info, "Removed #{source.name}. Its files were left alone.")
     |> load()}
  end

  def handle_event("delete-root", %{"id" => id}, socket) do
    root = Library.get_root!(id)
    {:ok, _root} = Library.delete_root(root)

    {:noreply,
     socket
     |> put_flash(:info, "Removed #{root.name}. Its files were left alone.")
     |> load()}
  end

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

  defp on_import_label(:bring_in), do: "brings files in"
  defp on_import_label(:leave_in_place), do: "leaves files in place"

  defp on_import_blurb(:bring_in),
    do: "Its files could vanish, so import places the library's own copy into a root."

  defp on_import_blurb(:leave_in_place),
    do: "Its files are trusted to stay. Imports reference them; Ambry never writes here."

  defp on_import_class(:bring_in), do: "bg-blue-400/15 text-blue-300"
  defp on_import_class(:leave_in_place), do: "bg-white/10 text-zinc-300"

  defp policy_label(:hardlink), do: "hardlink"
  defp policy_label(:copy), do: "copy"
  defp policy_label(:move), do: "move"
  defp policy_label(nil), do: nil

  defp source_problem(status) do
    cond do
      !status.exists? -> "Not found — is the volume mounted?"
      !status.directory? -> "Not a folder."
      true -> nil
    end
  end

  defp root_problem(status) do
    cond do
      !status.exists? -> "Not found — is the volume mounted?"
      !status.directory? -> "Not a folder."
      !status.writable? -> "Read-only, so nothing can land here."
      true -> nil
    end
  end

  defp scanned_label(nil), do: "never scanned"
  defp scanned_label(at), do: "scanned #{Calendar.strftime(at, "%x %X")}"
end
