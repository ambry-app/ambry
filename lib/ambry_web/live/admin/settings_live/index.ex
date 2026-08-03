defmodule AmbryWeb.Admin.SettingsLive.Index do
  @moduledoc """
  Server settings that aren't about any one record.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Settings

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign_settings()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.layout title={@page_title} user={@current_user}>
      <div class="mx-auto max-w-3xl space-y-8">
        <section>
          <h2 class="mb-1 text-lg font-bold">Direct play</h2>
          <p class="mb-4 text-sm text-zinc-500 dark:text-zinc-400">
            Direct-play recordings are served as their original files, with no transcoding or
            packaging. Publishing them has to wait for the apps: a client that predates track
            support can't play one, so leave this off until every device in the fleet is on a
            build that understands tracks.
          </p>

          <div class="rounded-sm border border-zinc-200 bg-zinc-50 p-4 dark:border-zinc-800 dark:bg-zinc-900">
            <div class="flex items-center gap-3">
              <span class={[
                "inline-block h-2.5 w-2.5 rounded-full",
                (@direct_play_publishing && "bg-lime-500") || "bg-zinc-400 dark:bg-zinc-600"
              ]} />
              <div class="grow">
                <h3 class="font-semibold">Publish direct-play recordings</h3>
                <p class="text-sm text-zinc-500 dark:text-zinc-400">
                  {publishing_blurb(@direct_play_publishing)}
                </p>
              </div>

              <.button phx-click="toggle-direct-play-publishing">
                {(@direct_play_publishing && "Turn off") || "Turn on"}
              </.button>
            </div>
          </div>
        </section>
      </div>
    </.layout>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-direct-play-publishing", _params, socket) do
    {:ok, _setting} = Settings.set_direct_play_publishing(!socket.assigns.direct_play_publishing)

    {:noreply, assign_settings(socket)}
  end

  defp assign_settings(socket) do
    assign(socket, :direct_play_publishing, Settings.direct_play_publishing?())
  end

  defp publishing_blurb(true), do: "Scanned recordings can be made visible to clients."

  defp publishing_blurb(false),
    do:
      "Recordings can be scanned, but one with only direct-play files can't be marked ready. " <>
        "The old transcoding pipeline is unaffected."
end
