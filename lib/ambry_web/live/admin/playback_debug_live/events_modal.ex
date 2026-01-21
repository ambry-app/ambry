defmodule AmbryWeb.Admin.PlaybackDebugLive.EventsModal do
  @moduledoc false
  use AmbryWeb, :live_component

  import Ecto.Query

  alias Ambry.Repo

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex h-full flex-col p-6">
      <div class="mb-4">
        <h2 class="text-2xl font-bold">Playback Events</h2>
        <p class="text-zinc-600 dark:text-zinc-400">
          {@playthrough.media.book.title} (ID: {@playthrough.id})
        </p>
      </div>

      <div class="flex-1 overflow-auto rounded border border-zinc-200 dark:border-zinc-700">
        <table class="w-full text-left text-sm">
          <thead class="sticky top-0 border-b border-zinc-200 bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800">
            <tr>
              <th class="px-4 py-2 font-medium">Type</th>
              <th class="px-4 py-2 font-medium">Timestamp</th>
              <th class="px-4 py-2 font-medium">Position</th>
              <th class="px-4 py-2 font-medium">Rate</th>
              <th class="px-4 py-2 font-medium">App</th>
              <th class="px-4 py-2 font-medium">Device</th>
              <th class="px-4 py-2 font-medium">Device ID</th>
              <th class="px-4 py-2 font-medium">ID</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200 dark:divide-zinc-700">
            <tr :for={event <- @events} class="hover:bg-zinc-50 dark:hover:bg-zinc-800/50">
              <td class="px-4 py-2">
                <span class={event_type_badge_class(event.type)}>
                  {event.type}
                </span>
              </td>
              <td class="font-mono whitespace-nowrap px-4 py-2 text-xs">
                {format_full_datetime(event.timestamp)}
              </td>
              <td class="font-mono whitespace-nowrap px-4 py-2 text-xs">
                <%= if event.type == :seek and event.from_position do %>
                  {Decimal.round(event.from_position, 1)} -> {Decimal.round(event.position, 1)}
                <% else %>
                  {event.position && Decimal.round(event.position, 1)}
                <% end %>
              </td>
              <td class="font-mono whitespace-nowrap px-4 py-2 text-xs">
                {event.playback_rate && Decimal.to_string(event.playback_rate)}
              </td>
              <td class="whitespace-nowrap px-4 py-2 text-xs">
                {format_app_version(event.app_version, event.app_build)}
              </td>
              <td class="max-w-[200px] truncate px-4 py-2 text-xs" title={format_device(event.device)}>
                {format_device(event.device)}
              </td>
              <td class="font-mono max-w-[100px] truncate px-4 py-2 text-xs" title={event.device && event.device.id}>
                {event.device && String.slice(event.device.id, 0, 8)}
              </td>
              <td class="font-mono max-w-[100px] truncate px-4 py-2 text-xs" title={event.id}>
                {String.slice(event.id, 0, 8)}
              </td>
            </tr>
            <tr :if={@events == []}>
              <td colspan="8" class="px-4 py-8 text-center text-zinc-500">No events found for this playthrough.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="mt-4 flex justify-end">
        <.button type="button" color={:zinc} phx-click={JS.exec("data-cancel", to: "#events-modal")}>
          Close
        </.button>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(events: list_events_for_playthrough(assigns.playthrough.id))}
  end

  defp list_events_for_playthrough(playthrough_id) do
    from(e in Ambry.Playback.PlaybackEvent,
      where: e.playthrough_id == ^playthrough_id,
      order_by: [desc: e.timestamp],
      preload: [:device]
    )
    |> Repo.all()
  end

  defp format_full_datetime(nil), do: nil

  defp format_full_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp event_type_badge_class(type) when type in [:play, :pause, :seek, :rate_change],
    do: "rounded px-1 text-xs bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

  defp event_type_badge_class(type) when type in [:start, :finish, :abandon, :resume],
    do:
      "rounded px-1 text-xs bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200"

  defp event_type_badge_class(_type),
    do: "rounded px-1 text-xs bg-zinc-100 text-zinc-800 dark:bg-zinc-700 dark:text-zinc-200"

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
