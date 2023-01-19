defmodule AmbryWeb.PlayerLive.Player do
  @moduledoc false

  use AmbryWeb, :live_view

  alias Ambry.Media

  on_mount {AmbryWeb.UserAuth, :ensure_authenticated}
  on_mount AmbryWeb.PlayerStateHooks

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div id="media-player" phx-hook="mediaPlayer" {player_state_attrs(@player_state)}>
      <audio />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(:not_mounted_at_router, _session, socket) do
    {:ok, socket, layout: false}
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

  @impl Phoenix.LiveView
  def handle_event("playback-time-updated", %{"playback-time" => playback_time}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        position: playback_time
      })

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("playback-rate-changed", %{"playback-rate" => playback_rate}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        playback_rate: playback_rate
      })

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("load-media", %{"media-id" => media_id}, socket) do
    %{current_user: user} = socket.assigns
    player_state = Media.load_player_state!(user, media_id)

    {:noreply,
     socket
     |> assign(:player_state, player_state)
     |> push_event("reload-media", %{})}
  end
end

# def footer(assigns) do
#   ~H"""
#   <footer
#     x-data
#     class={"bg-gray-100 dark:bg-gray-900" <> if @player_state, do: "", else: " hidden"}
#     x-effect="$store.player.mediaId ? $el.classList.remove('hidden') : null"
#   >
#     <.time_bar player_state={@player_state} />
#     <.player_controls player_state={@player_state} />
#   </footer>
#   """
# end

# defp time_bar(assigns) do
#   ~H"""
#   <div
#     x-data="
#       {
#         position: 0,
#         ratio: 0,
#         percent: 0,
#         time: 0,
#         width: 0,
#         dragging: false,
#         update (x) {
#           if (this.width && $store.player.duration.real) {
#             this.position = Math.min(x, this.width)
#             this.ratio = this.position / this.width
#             this.percent = (this.ratio * 100).toFixed(2)
#             this.time = this.ratio * $store.player.duration.real
#           }
#         },
#         startDrag (event) {
#           if (event.buttons === 1) {
#             this.dragging = true
#           }
#         },
#         endDrag () {
#           if (this.dragging) {
#             this.dragging = false
#             mediaPlayer.seekRatio(this.ratio)
#             $store.player.progress.percent = this.percent
#           }
#         }
#       }
#     "
#     x-init="width = $el.clientWidth"
#     class="group cursor-pointer h-[32px] -mt-[16px] relative mr-[12px]"
#     @resize.window="width = $el.clientWidth"
#     @mousemove.window="dragging && update($event.clientX)"
#     @mousemove="!dragging && update($event.clientX)"
#     @mousedown.prevent="startDrag($event)"
#     @mouseup.window="endDrag()"
#   >
#     <div
#       class="absolute border bg-gray-100 border-gray-200 dark:bg-gray-900 dark:border-gray-800 px-1 -top-4 rounded-sm hidden group-hover:block pointer-events-none tabular-nums"
#       :class="{ 'hidden': !dragging }"
#       :style="position > width / 2 ? `right: ${width - position}px` : `left: ${position}px`"
#       x-text="formatTimecode(time)"
#     />
#     <div class="relative top-[16px] bg-gray-200 dark:bg-gray-800">
#       <div
#         class="h-[2px] group-hover:h-[4px] bg-lime-500 dark:bg-lime-400"
#         :class="{ 'h-[4px]': dragging }"
#         style={"width: #{progress_percent(@player_state)}%"}
#         :style={
#           "$store.player.progress.percent ? `width: ${dragging ? percent : $store.player.progress.percent}%` : 'width: #{progress_percent(@player_state)}%'"
#         }
#       />
#       <div
#         class="absolute hidden group-hover:block bg-lime-500 dark:bg-lime-400 rounded-full w-[16px] h-[16px] top-[-6px] pointer-events-none"
#         :class="{ 'hidden': !dragging }"
#         style="left: calc(0% - 8px)"
#         :style="`left: calc(${dragging ? percent : $store.player.progress.percent}% - 8px)`"
#       />
#     </div>
#   </div>
#   """
# end

# defp progress_percent(nil), do: "0.0"

# defp progress_percent(%{position: position, media: %{duration: duration}}) do
#   position
#   |> Decimal.div(duration)
#   |> Decimal.mult(100)
#   |> Decimal.round(1)
#   |> Decimal.to_string()
# end

# defp player_controls(assigns) do
#   ~H"""
#   <div x-data class="!pt-0 p-4 flex gap-6 items-center text-gray-900 dark:text-gray-100 fill-current">
#     <span @click="mediaPlayer.seekRelative(-60)" class="cursor-pointer" title="Back 1 minute">
#       <FA.icon name="backward-step" class="w-4 h-4 sm:w-5 sm:h-5" />
#     </span>
#     <span @click="mediaPlayer.seekRelative(-10)" class="cursor-pointer" title="Back 10 seconds">
#       <FA.icon name="rotate-left" class="w-4 h-4 sm:w-5 sm:h-5" />
#     </span>
#     <span @click="mediaPlayer.playPause()" class="cursor-pointer" title="Play">
#       <span :class="{ hidden: $store.player.playing }">
#         <FA.icon name="play" class="w-6 h-6 sm:w-7 sm:h-7" />
#       </span>
#       <span class="hidden" :class="{ hidden: !$store.player.playing }">
#         <FA.icon name="pause" class="w-6 h-6 sm:w-7 sm:h-7" />
#       </span>
#     </span>
#     <span @click="mediaPlayer.seekRelative(10)" class="cursor-pointer" title="Forward 10 seconds">
#       <FA.icon name="rotate-right" class="w-4 h-4 sm:w-5 sm:h-5" />
#     </span>
#     <span @click="mediaPlayer.seekRelative(60)" class="cursor-pointer" title="Forward 1 minute">
#       <FA.icon name="forward-step" class="w-4 h-4 sm:w-5 sm:h-5" />
#     </span>
#     <div class="text-gray-600 dark:text-gray-500 text-sm sm:text-base whitespace-nowrap tabular-nums">
#       <.alpine_value_with_fallback
#         alpine_value="$store.player.progress.real"
#         alpine_expression="formatTimecode($store.player.progress.real)"
#         fallback={player_state_progress(@player_state)}
#       />
#       <span class="hidden sm:inline">/</span>
#       <span class="hidden sm:inline">
#         <.alpine_value_with_fallback
#           alpine_value="$store.player.duration.real"
#           alpine_expression="formatTimecode($store.player.duration.real)"
#           fallback={player_state_duration(@player_state)}
#         />
#       </span>
#     </div>
#     <div class="flex-grow text-ellipsis whitespace-nowrap overflow-hidden">
#       <span class="text-gray-800 dark:text-gray-300 text-sm sm:text-base">
#         <%= player_state_description(@player_state) %>
#       </span>
#     </div>
#     <div
#       x-data="{
#         open: false,
#         close () { this.open = false },
#         inc () {
#           mediaPlayer.setPlaybackRate(Math.min($store.player.playbackRate + 0.05, 3.0))
#         },
#         dec () {
#           mediaPlayer.setPlaybackRate(Math.max($store.player.playbackRate - 0.05, 0.5))
#         }
#       }"
#       @click.outside="open = false"
#       @keydown.escape.window.prevent="open = false"
#       title="Playback speed"
#       class="flex gap-2 items-center"
#     >
#       <div @click="open = !open" class="flex gap-2 items-center cursor-pointer">
#         <span class="hidden sm:block text-gray-600 dark:text-gray-500 text-sm sm:text-base">
#           <.alpine_value_with_fallback
#             alpine_value="$store.player.playbackRate"
#             alpine_expression="formatDecimal($store.player.playbackRate)"
#             fallback={player_state_playback_rate(@player_state)}
#           />x
#         </span>
#         <FA.icon name="gauge-high" class="w-4 h-4 sm:w-5 sm:h-5" />
#       </div>
#       <.playback_rate_menu />
#     </div>
#   </div>
#   """
# end

# defp player_state_progress(nil), do: "--:--"

# defp player_state_progress(%{playback_rate: playback_rate, position: position}) do
#   format_timecode(Decimal.div(position, playback_rate))
# end

# defp player_state_duration(nil), do: "--:--"

# defp player_state_duration(%{playback_rate: playback_rate, media: %{duration: duration}}) do
#   format_timecode(Decimal.div(duration, playback_rate))
# end

# defp player_state_playback_rate(nil), do: "1.0"

# defp player_state_playback_rate(%{playback_rate: playback_rate}) do
#   format_decimal(playback_rate)
# end

# defp player_state_description(nil), do: ""

# defp player_state_description(%{media: media}) do
#   Media.get_media_description(media)
# end

# defp format_decimal(decimal) do
#   rounded = Decimal.round(decimal, 1)

#   if Decimal.equal?(rounded, decimal), do: rounded, else: decimal
# end

# defp alpine_value_with_fallback(assigns) do
#   ~H"""
#   <span x-text={"#{@alpine_value} !== undefined ? #{@alpine_expression} : '#{@fallback}'"}><%= @fallback %></span>
#   """
# end

# defp playback_rate_menu(assigns) do
#   ~H"""
#   <div
#     :class="{ 'hidden': !open }"
#     class="hidden absolute bottom-12 right-4 max-w-80 text-gray-800 dark:text-gray-200 z-50 shadow-md"
#   >
#     <div class="w-full h-full bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-sm divide-y divide-gray-200 dark:divide-gray-800">
#       <div class="p-3">
#         <p class="text-center font-bold text-lg sm:text-xl">
#           <span x-text="formatDecimal($store.player.playbackRate)" />x
#         </p>
#       </div>
#       <div>
#         <div class="flex divide-x divide-gray-200 dark:divide-gray-800">
#           <div @click="dec()" class="p-4 flex-grow cursor-pointer hover:bg-gray-300 dark:hover:bg-gray-700">
#             <FA.icon name="minus" class="w-4 h-4 sm:w-5 sm:h-5 mx-auto" />
#           </div>
#           <div @click="inc()" class="p-4 flex-grow cursor-pointer hover:bg-gray-300 dark:hover:bg-gray-700">
#             <FA.icon name="plus" class="w-4 h-4 sm:w-5 sm:h-5 mx-auto" />
#           </div>
#         </div>
#       </div>
#       <div class="flex py-3 tabular-nums sm:text-lg">
#         <span
#           @click="mediaPlayer.setPlaybackRate('1.0'); close()"
#           class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
#         >
#           1.0x
#         </span>
#         <span
#           @click="mediaPlayer.setPlaybackRate('1.25'); close()"
#           class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
#         >
#           1.25x
#         </span>
#         <span
#           @click="mediaPlayer.setPlaybackRate('1.5'); close()"
#           class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
#         >
#           1.5x
#         </span>
#         <span
#           @click="mediaPlayer.setPlaybackRate('1.75'); close()"
#           class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
#         >
#           1.75x
#         </span>
#         <span
#           @click="mediaPlayer.setPlaybackRate('2.0'); close()"
#           class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
#         >
#           2.0x
#         </span>
#       </div>
#     </div>
#   </div>
#   """
# end
