defmodule AmbryWeb.Admin.InboxLive.Index do
  @moduledoc """
  The curation queue: what discovery found, what it is, and what it claims
  about itself.

  Deliberately plain — the inbox is the surface the admin redesign will be
  built around, so this is the least that makes the workflow usable.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.TimeUtils

  alias Ambry.Inbox
  alias Ambry.Inbox.InboxItem

  @statuses [:pending, :dismissed, :approved]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Inbox", show_header_search: true)
     |> load_items(params)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> load_items(params)}
  end

  @impl Phoenix.LiveView
  def handle_event("scan", _params, socket) do
    case Inbox.discover_async() do
      {:ok, _job} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Scanning the watched folder. Nothing is moved or changed — new candidates just show up here."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't start a scan.")}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    {:ok, _item} = id |> Inbox.get_item!() |> Inbox.dismiss_item()

    {:noreply, socket |> put_flash(:info, "Dismissed. Files untouched.") |> reload()}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    {:ok, _item} = id |> Inbox.get_item!() |> Inbox.restore_item()

    {:noreply, reload(socket)}
  end

  def handle_event("reprobe", %{"id" => id}, socket) do
    {:ok, _job} = id |> Inbox.get_item!() |> Inbox.probe_item_async()

    {:noreply, put_flash(socket, :info, "Re-reading the files.")}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/inbox?#{patch(socket, filter: query, page: "1")}")}
  end

  def handle_event("filter-status", %{"status" => status}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/inbox?#{patch(socket, status: status, page: "1")}")}
  end

  defp load_items(socket, params) do
    list_opts = get_list_opts(params)
    status = parse_status(params["status"])

    {items, has_more?} =
      Inbox.list_items(
        status: status,
        filter: list_opts.filter,
        offset: page_to_offset(list_opts.page),
        limit: limit()
      )

    socket
    |> assign(
      items: items,
      counts: Inbox.count_by_status(),
      status: status,
      list_opts: list_opts,
      has_next: has_more?,
      has_prev: list_opts.page > 1,
      next_page_path: ~p"/admin/inbox?#{patch_opts(next_opts(list_opts))}",
      prev_page_path: ~p"/admin/inbox?#{patch_opts(prev_opts(list_opts))}"
    )
    |> assign(:statuses, @statuses)
  end

  defp reload(socket), do: load_items(socket, patch(socket, []))

  # Blank values are dropped rather than passed as nil: the shared pagination
  # helpers read params with `Map.get(params, "filter", "")`, which only
  # defaults on a *missing* key, so an explicit nil would crash on trim.
  defp patch(socket, overrides) do
    %{
      "filter" => Keyword.get(overrides, :filter, socket.assigns.list_opts.filter),
      "page" => Keyword.get(overrides, :page, to_string(socket.assigns.list_opts.page)),
      "status" =>
        Keyword.get(overrides, :status, socket.assigns.status && to_string(socket.assigns.status))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp parse_status(status) when status in ["pending", "dismissed", "approved"],
    do: String.to_existing_atom(status)

  defp parse_status(_anything), do: nil

  defp status_color(:pending), do: :yellow
  defp status_color(:approved), do: :brand
  defp status_color(:dismissed), do: :gray

  @doc """
  The candidate's name — usually the release name, and the most recognizable
  thing about it.
  """
  def item_name(item), do: InboxItem.name(item)

  @doc """
  A one-line summary of what the file says it is, which is what makes an item
  identifiable at a glance before anything has been matched.
  """
  def tag_summary(%InboxItem{tags: tags}) when is_map(tags) do
    [
      tags["book_title"],
      join_names(tags["authors"]),
      narrated_by(tags["narrators"]),
      series_label(tags)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  def tag_summary(_item), do: ""

  defp narrated_by(nil), do: nil
  defp narrated_by([]), do: nil
  defp narrated_by(names), do: "read by #{join_names(names)}"

  defp join_names(nil), do: nil
  defp join_names([]), do: nil
  defp join_names(names), do: Enum.join(names, ", ")

  defp series_label(%{"series" => nil}), do: nil
  defp series_label(%{"series" => series, "series_number" => nil}), do: series
  defp series_label(%{"series" => series, "series_number" => number}), do: "#{series} ##{number}"
  defp series_label(_tags), do: nil

  @doc """
  What the files actually are, as probed — the facts, as opposed to the
  claims in `tag_summary/1`.
  """
  def probe_summary(%InboxItem{probe: probe}) when is_map(probe) do
    [
      probe["duration"] && format_timecode(Decimal.new(probe["duration"])),
      probe["codec"],
      probe["chapters"] && probe["chapters"] > 0 && "#{probe["chapters"]} chapters",
      probe["seek_accuracy"] == "approximate" && "inexact seeking"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  def probe_summary(_item), do: ""

  def file_count(%InboxItem{files: files}), do: length(files)
end
