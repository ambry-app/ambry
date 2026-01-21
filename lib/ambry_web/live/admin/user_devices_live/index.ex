defmodule AmbryWeb.Admin.UserDevicesLive.Index do
  @moduledoc """
  Admin view for user devices.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Accounts
  alias Ambry.Playback

  @valid_sort_fields [
    :type,
    :brand,
    :model_name,
    :os_name,
    :browser,
    :app_id,
    :last_seen_at,
    :event_count
  ]

  @default_sort "last_seen_at.desc"

  @impl Phoenix.LiveView
  def mount(%{"user_id" => user_id} = params, _session, socket) do
    user = Accounts.get_user!(user_id)

    socket =
      socket
      |> assign(
        page_title: "Devices for #{user.email}",
        selected_user: user,
        devices: [],
        show_header_search: true,
        has_next: false,
        has_prev: false,
        next_page_path: "#",
        prev_page_path: "#",
        current_sort: @default_sort,
        list_opts: %{page: 1, filter: nil, sort: nil}
      )
      |> maybe_update_devices(params, true)

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_devices(params, true)}
  end

  defp maybe_update_devices(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {devices, has_more?} = list_devices(socket.assigns.selected_user.id, list_opts)

      assign(socket,
        list_opts: list_opts,
        devices: devices,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path:
          ~p"/admin/users/#{socket.assigns.selected_user.id}/devices?#{next_opts(list_opts)}",
        prev_page_path:
          ~p"/admin/users/#{socket.assigns.selected_user.id}/devices?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_devices(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)
    user_id = socket.assigns.selected_user.id

    {:noreply,
     push_patch(socket,
       to: ~p"/admin/users/#{user_id}/devices?#{patch_opts(list_opts)}"
     )}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    user_id = socket.assigns.selected_user.id

    {:noreply,
     push_patch(socket,
       to: ~p"/admin/users/#{user_id}/devices?#{patch_opts(list_opts)}"
     )}
  end

  defp list_devices(user_id, opts) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}
    filters = Map.put(filters, :user_id, user_id)

    Playback.list_devices_flat(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || @default_sort, @valid_sort_fields)
    )
  end

  defp format_date(nil), do: "-"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%x")
  end

  defp format_full_datetime(nil), do: nil

  defp format_full_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  # Device display helpers

  defp format_device(nil), do: nil

  defp format_device(device) do
    case device.type do
      :web -> format_web_device(device)
      _ -> format_mobile_device(device)
    end
  end

  defp format_mobile_device(device) do
    model = device.model_name || device.brand || to_string(device.type)
    os = format_os(device.os_name, device.os_version)

    [model, os]
    |> Enum.filter(& &1)
    |> Enum.join(" / ")
  end

  defp format_web_device(device) do
    browser = format_browser(device.browser, device.browser_version)
    os = device.os_name

    case {browser, os} do
      {nil, nil} -> "Web"
      {nil, os} -> "Web (#{os})"
      {browser, nil} -> browser
      {browser, os} -> "#{browser} (#{os})"
    end
  end

  defp format_os(nil, _), do: nil
  defp format_os(name, nil), do: name
  defp format_os(name, version), do: "#{name} #{version}"

  defp format_browser(nil, _), do: nil
  defp format_browser(name, nil), do: name
  defp format_browser(name, version), do: "#{name} #{version}"

  defp format_app_version(nil, nil), do: nil
  defp format_app_version(version, nil), do: "v#{version}"
  defp format_app_version(nil, build), do: "build #{build}"
  defp format_app_version(version, build), do: "v#{version} (#{build})"
end
