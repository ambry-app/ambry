defmodule AmbryWeb.PlayerLive.Player.Components do
  @moduledoc """
  Components for the player live page.
  """

  use AmbryWeb, :html

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias Ambry.Media

  def media_player(assigns) do
    ~H"""
    <div id="media-player" phx-hook="mediaPlayer" {player_state_attrs(@player_state)}>
      <audio />
    </div>
    """
  end

  defp player_state_attrs(nil), do: %{"data-media-unloaded" => true}

  defp player_state_attrs(%Media.PlayerState{
         media: %Media.Media{id: id, mpd_path: path},
         position: position,
         playback_rate: playback_rate
       }) do
    %{
      "data-media-id" => id,
      "data-media-position" => position,
      "data-media-path" => "#{path}#t=#{position}",
      "data-media-playback-rate" => playback_rate
    }
  end

  def time_bar(assigns) do
    ~H"""
    <div class="group absolute -top-4 h-8 w-full cursor-pointer">
      <!-- TODO: time text label -->
      <%!-- <div
        class="pointer-events-none absolute -top-4 hidden rounded-sm border border-zinc-200 bg-zinc-100 px-1 tabular-nums group-hover:block dark:border-zinc-800 dark:bg-zinc-900"
        x-class="{ 'hidden': !dragging }"
        x-style="position > width / 2 ? `right: ${width - position}px` : `left: ${position}px`"
        x-text="formatTimecode(time)"
      /> --%>
      <div class="mr-[12px] relative top-4 bg-zinc-200 dark:bg-zinc-800">
        <div
          class="h-[2px] bg-brand group-hover:h-[4px] dark:bg-brand-dark"
          style={"width: #{progress_percent(@player_state)}%"}
        />
        <div
          class="top-[-6px] bg-brand pointer-events-none absolute hidden h-4 w-4 rounded-full group-hover:block dark:bg-brand-dark"
          style={"left: calc(#{progress_percent(@player_state)}% - 8px)"}
        />
      </div>
    </div>
    """
  end

  defp progress_percent(nil), do: "0.0"

  defp progress_percent(%{position: position, media: %{duration: duration}}) do
    position
    |> Decimal.div(duration)
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  def player_controls(assigns) do
    ~H"""
    <div x-data class="flex items-center gap-6 fill-current p-4 text-zinc-900 dark:text-zinc-100">
      <span @click="mediaPlayer.seekRelative(-60)" class="cursor-pointer" title="Back 1 minute">
        <FA.icon name="backward-step" class="h-4 w-4 sm:h-5 sm:w-5" />
      </span>
      <span @click="mediaPlayer.seekRelative(-10)" class="cursor-pointer" title="Back 10 seconds">
        <FA.icon name="rotate-left" class="h-4 w-4 sm:h-5 sm:w-5" />
      </span>
      <span @click="mediaPlayer.playPause()" class="cursor-pointer" title="Play">
        <span x-class="{ hidden: $store.player.playing }">
          <FA.icon name="play" class="h-6 w-6 sm:h-7 sm:w-7" />
        </span>
        <span class="hidden" x-class="{ hidden: !$store.player.playing }">
          <FA.icon name="pause" class="h-6 w-6 sm:h-7 sm:w-7" />
        </span>
      </span>
      <span @click="mediaPlayer.seekRelative(10)" class="cursor-pointer" title="Forward 10 seconds">
        <FA.icon name="rotate-right" class="h-4 w-4 sm:h-5 sm:w-5" />
      </span>
      <span @click="mediaPlayer.seekRelative(60)" class="cursor-pointer" title="Forward 1 minute">
        <FA.icon name="forward-step" class="h-4 w-4 sm:h-5 sm:w-5" />
      </span>
      <div class="whitespace-nowrap text-sm tabular-nums text-zinc-600 dark:text-zinc-500 sm:text-base">
        <.alpine_value_with_fallback
          alpine_value="$store.player.progress.real"
          alpine_expression="formatTimecode($store.player.progress.real)"
          fallback={player_state_progress(@player_state)}
        />
        <span class="hidden sm:inline">/</span>
        <span class="hidden sm:inline">
          <.alpine_value_with_fallback
            alpine_value="$store.player.duration.real"
            alpine_expression="formatTimecode($store.player.duration.real)"
            fallback={player_state_duration(@player_state)}
          />
        </span>
      </div>
      <div class="grow overflow-hidden text-ellipsis whitespace-nowrap">
        <span class="text-sm text-zinc-800 dark:text-zinc-300 sm:text-base">
          <%= player_state_description(@player_state) %>
        </span>
      </div>
      <div
        x-data="{
          open: false,
          close () { this.open = false },
          inc () {
            mediaPlayer.setPlaybackRate(Math.min($store.player.playbackRate + 0.05, 3.0))
          },
          dec () {
            mediaPlayer.setPlaybackRate(Math.max($store.player.playbackRate - 0.05, 0.5))
          }
        }"
        @click.outside="open = false"
        @keydown.escape.window.prevent="open = false"
        title="Playback speed"
        class="flex items-center gap-2"
      >
        <div @click="open = !open" class="flex cursor-pointer items-center gap-2">
          <span class="hidden text-sm text-zinc-600 dark:text-zinc-500 sm:block sm:text-base">
            <.alpine_value_with_fallback
              alpine_value="$store.player.playbackRate"
              alpine_expression="formatDecimal($store.player.playbackRate)"
              fallback={player_state_playback_rate(@player_state)}
            />x
          </span>
          <FA.icon name="gauge-high" class="h-4 w-4 sm:h-5 sm:w-5" />
        </div>
        <.playback_rate_menu />
      </div>
    </div>
    """
  end

  defp player_state_progress(nil), do: "--:--"

  defp player_state_progress(%{playback_rate: playback_rate, position: position}) do
    format_timecode(Decimal.div(position, playback_rate))
  end

  defp player_state_duration(nil), do: "--:--"

  defp player_state_duration(%{playback_rate: playback_rate, media: %{duration: duration}}) do
    format_timecode(Decimal.div(duration, playback_rate))
  end

  defp player_state_playback_rate(nil), do: "1.0"

  defp player_state_playback_rate(%{playback_rate: playback_rate}) do
    format_decimal(playback_rate)
  end

  defp player_state_description(nil), do: ""

  defp player_state_description(%{media: media}) do
    Media.get_media_description(media)
  end

  defp format_decimal(decimal) do
    rounded = Decimal.round(decimal, 1)

    if Decimal.equal?(rounded, decimal), do: rounded, else: decimal
  end

  defp alpine_value_with_fallback(assigns) do
    ~H"""
    <span x-text={"#{@alpine_value} !== undefined ? #{@alpine_expression} : '#{@fallback}'"}><%= @fallback %></span>
    """
  end

  defp playback_rate_menu(assigns) do
    ~H"""
    <div
      x-class="{ 'hidden': !open }"
      class="max-w-80 absolute right-4 bottom-12 z-50 hidden text-zinc-800 shadow-md dark:text-zinc-200"
    >
      <div class="h-full w-full divide-y divide-zinc-200 rounded-sm border border-zinc-200 bg-zinc-50 dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900">
        <div class="p-3">
          <p class="text-center text-lg font-bold sm:text-xl">
            <span x-text="formatDecimal($store.player.playbackRate)" />x
          </p>
        </div>
        <div>
          <div class="flex divide-x divide-zinc-200 dark:divide-zinc-800">
            <div @click="dec()" class="grow cursor-pointer p-4 hover:bg-zinc-300 dark:hover:bg-zinc-700">
              <FA.icon name="minus" class="mx-auto h-4 w-4 sm:h-5 sm:w-5" />
            </div>
            <div @click="inc()" class="grow cursor-pointer p-4 hover:bg-zinc-300 dark:hover:bg-zinc-700">
              <FA.icon name="plus" class="mx-auto h-4 w-4 sm:h-5 sm:w-5" />
            </div>
          </div>
        </div>
        <div class="flex py-3 tabular-nums sm:text-lg">
          <span
            @click="mediaPlayer.setPlaybackRate('1.0'); close()"
            class="cursor-pointer px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
          >
            1.0x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('1.25'); close()"
            class="cursor-pointer px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
          >
            1.25x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('1.5'); close()"
            class="cursor-pointer px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
          >
            1.5x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('1.75'); close()"
            class="cursor-pointer px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
          >
            1.75x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('2.0'); close()"
            class="cursor-pointer px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
          >
            2.0x
          </span>
        </div>
      </div>
    </div>
    """
  end
end
