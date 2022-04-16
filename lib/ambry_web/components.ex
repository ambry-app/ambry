defmodule AmbryWeb.Components do
  @moduledoc """
  Shared function components used throughout the app.
  """

  use AmbryWeb, :component

  import AmbryWeb.TimeUtils

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  alias AmbryWeb.Components.SearchBox
  alias AmbryWeb.Endpoint
  alias AmbryWeb.Router.Helpers, as: Routes

  def ambry_icon(assigns) do
    extra_classes = assigns[:class] || ""
    default_classes = "text-lime-500 dark:text-lime-400"
    assigns = assign(assigns, :class, String.trim("#{default_classes} #{extra_classes}"))

    ~H"""
    <svg class={@class} version="1.1" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path
        d="m512 287.9-4e-3 112c-0.896 44.2-35.896 80.1-79.996 80.1-26.47 0-48-21.56-48-48.06v-127.84c0-26.5 21.5-48.1 48-48.1 10.83 0 20.91 2.723 30.3 6.678-12.6-103.58-100.2-182.55-206.3-182.55s-193.71 78.97-206.3 182.57c9.39-4 19.47-6.7 30.3-6.7 26.5 0 48 21.6 48 48.1v127.9c0 26.4-21.5 48-48 48-44.11 0-79.1-35.88-79.1-80.06l-0.9-111.94c0-141.2 114.8-256 256-256 140.9 0 256.5 114.56 256 255.36 0 0.2 0 0-2e-3 0.54451z"
        fill="currentColor"
      />
      <path
        d="m364 347v-138.86c0-12.782-10.366-23.143-23.143-23.143h-146.57c-25.563 0-46.286 20.723-46.286 46.286v154.29c0 25.563 20.723 46.286 46.286 46.286h154.29c8.5195 0 15.429-6.9091 15.429-14.995 0-5.6507-3.1855-10.376-7.7143-13.066v-39.227c4.725-4.6479 7.7143-10.723 7.7143-17.569zm-147.01-100.29h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143s-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143s3.4714-7.7143 7.2804-7.7143zm0 30.857h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143 0 4.2429-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143 0-4.2429 3.4714-7.7143 7.2804-7.7143zm116.15 123.43h-138.86c-8.5195 0-15.429-6.9091-15.429-15.429 0-8.5195 6.9091-15.429 15.429-15.429h138.86z"
        fill="currentColor"
      />
    </svg>
    """
  end

  def ambry_title(assigns) do
    extra_classes = assigns[:class] || ""
    default_classes = "text-gray-900 dark:text-gray-100"
    assigns = assign(assigns, :class, String.trim("#{default_classes} #{extra_classes}"))

    ~H"""
    <svg class={@class} version="1.1" viewBox="0 0 1536 512" xmlns="http://www.w3.org/2000/svg">
      <g fill="currentColor">
        <path d="m283.08 388.31h-123.38l-24 91.692h-95.692l140-448h82.769l140.92 448h-96.615zm-103.69-75.385h83.692l-41.846-159.69z" />
        <g>
          <path d="m533.4 146.87 62.92 240.93 62.691-240.93h87.859v333.13h-67.496v-90.147l6.1776-138.88-66.581 229.03h-45.76l-66.581-229.03 6.1775 138.88v90.147h-67.267v-333.13z" />
          <path d="m800.87 480v-333.13h102.96q52.166 0 79.165 23.338 27.227 23.109 27.227 67.953 0 25.397-11.211 43.701-11.211 18.304-30.659 26.77 22.422 6.4064 34.549 25.854 12.126 19.219 12.126 47.59 0 48.506-26.77 73.216-26.541 24.71-77.105 24.71zm67.267-144.83v89.003h43.014q18.075 0 27.456-11.211 9.3809-11.211 9.3809-31.803 0-44.845-32.49-45.989zm0-48.963h35.006q39.582 0 39.582-40.955 0-22.651-9.152-32.49t-29.744-9.8384h-35.693z" />
          <path d="m1164.7 358.28h-33.405v121.72h-67.267v-333.13h107.31q50.565 0 78.02 26.312 27.685 26.083 27.685 74.36 0 66.352-48.277 92.893l58.344 136.36v3.2032h-72.301zm-33.405-56.056h38.21q20.134 0 30.202-13.27 10.067-13.499 10.067-35.922 0-50.107-39.125-50.107h-39.354z" />
          <path d="m1412.7 296.5 50.107-149.63h73.216l-89.232 212.33v120.81h-68.182v-120.81l-89.461-212.33h73.216z" />
        </g>
      </g>
    </svg>
    """
  end

  def header(assigns) do
    ~H"""
    <header x-data class="border-gray-100 dark:border-gray-900" :class="{ 'border-b': $store.header.scrolled }">
      <div class="p-4 flex text-gray-600 dark:text-gray-500">
        <div class="flex-1">
          <.link link_type="live_redirect" to="/" class="flex">
            <.ambry_icon class="mt-1 w-6 h-6 lg:w-7 lg:h-7" />
            <.ambry_title class="mt-1 h-6 lg:h-7 hidden md:block" />
          </.link>
        </div>
        <div class="flex-1">
          <div class="flex justify-center gap-8 lg:gap-12">
            <.link
              link_type="live_redirect"
              to={Routes.now_playing_index_path(Endpoint, :index)}
              class={nav_class(@active_path == "/")}
            >
              <span title="Now playing"><FA.icon name="circle-play" class="mt-1 w-6 h-6 lg:hidden fill-current" /></span>
              <span class="hidden lg:block font-bold text-xl">Now Playing</span>
            </.link>
            <.link
              link_type="live_redirect"
              to={Routes.library_home_path(Endpoint, :home)}
              class={nav_class(@active_path == "/library")}
            >
              <span title="Library"><FA.icon name="book-open" class="mt-1 w-6 h-6 lg:hidden fill-current" /></span>
              <span class="hidden lg:block font-bold text-xl">Library</span>
            </.link>
            <span
              x-data
              @click="$nextTick(() => $store.search.open = true)"
              class={nav_class(false, "flex content-center gap-4 cursor-pointer")}
            >
              <span title="Search">
                <FA.icon name="magnifying-glass" class="mt-1 w-6 h-6 lg:w-5 lg:h-5 fill-current" />
              </span>
              <span class="hidden xl:block font-bold text-xl">Search</span>
            </span>
          </div>
        </div>
        <div class="flex-1">
          <div class="flex">
            <div class="flex-grow" />
            <div x-data="{ open: false }" @click.outside="open = false" @keydown.escape.window.prevent="open = false">
              <img
                @click="open = !open"
                class="mt-1 h-6 lg:w-7 lg:h-7 rounded-full cursor-pointer"
                src={gravatar_url(@user.email)}
              />
              <.user_menu user={@user} />
            </div>
          </div>
        </div>
      </div>

      <.live_component module={SearchBox} id="search-box" />
    </header>
    """
  end

  defp nav_class(active?, extra \\ "")
  defp nav_class(true, extra), do: "text-gray-900 dark:text-gray-100 #{extra}"
  defp nav_class(false, extra), do: "hover:text-gray-900 dark:hover:text-gray-100 #{extra}"

  def user_menu(assigns) do
    ~H"""
    <.menu_wrapper user={@user}>
      <div class="py-3">
        <%= if @user.admin do %>
          <.link
            link_type="live_redirect"
            to={Routes.admin_home_index_path(Endpoint, :index)}
            class="flex items-center px-4 py-2 gap-4 hover:bg-gray-300 dark:hover:bg-gray-700"
          >
            <FA.icon name="screwdriver-wrench" class="w-5 h-5 fill-current" />
            <p>Admin</p>
          </.link>
        <% end %>
        <.link
          to={Routes.user_settings_path(Endpoint, :edit)}
          class="flex items-center px-4 py-2 gap-4 hover:bg-gray-300 dark:hover:bg-gray-700"
        >
          <FA.icon name="user-gear" class="w-5 h-5 fill-current" />
          <p>Account Settings</p>
        </.link>
        <.link
          to={Routes.user_session_path(Endpoint, :delete)}
          method="delete"
          class="flex items-center px-4 py-2 gap-4 hover:bg-gray-300 dark:hover:bg-gray-700"
        >
          <FA.icon name="arrow-right-from-bracket" class="w-5 h-5 fill-current" />
          <p>Log out</p>
        </.link>
      </div>
    </.menu_wrapper>
    """
  end

  def admin_menu(assigns) do
    ~H"""
    <.menu_wrapper user={@user}>
      <div class="py-3">
        <.link
          link_type="live_redirect"
          to="/"
          class="flex items-center px-4 py-2 gap-4 hover:bg-gray-300 dark:hover:bg-gray-700"
        >
          <FA.icon name="arrow-right-from-bracket" class="w-5 h-5 fill-current scale-[-1]" />
          <p>Exit Admin</p>
        </.link>
        <.link
          to={Routes.user_session_path(Endpoint, :delete)}
          method="delete"
          class="flex items-center px-4 py-2 gap-4 hover:bg-gray-300 dark:hover:bg-gray-700"
        >
          <FA.icon name="arrow-right-from-bracket" class="w-5 h-5 fill-current" />
          <p>Log out</p>
        </.link>
      </div>
    </.menu_wrapper>
    """
  end

  defp menu_wrapper(assigns) do
    ~H"""
    <div
      :class="{ 'hidden': !open }"
      class="hidden absolute top-12 right-4 max-w-80 text-gray-800 dark:text-gray-200 z-50 shadow-md"
    >
      <div class="w-full h-full bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-sm divide-y divide-gray-200 dark:divide-gray-800">
        <div class="flex items-center p-4 gap-4">
          <img class="w-10 h-10 rounded-full" src={gravatar_url(@user.email)} />
          <p class="whitespace-nowrap overflow-hidden text-ellipsis"><%= @user.email %></p>
        </div>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def footer(assigns) do
    ~H"""
    <footer
      x-data
      class={"bg-gray-100 dark:bg-gray-900" <> if @player_state, do: "", else: " hidden"}
      x-effect="$store.player.mediaId ? $el.classList.remove('hidden') : null"
    >
      <.time_bar player_state={@player_state} />
      <.player_controls player_state={@player_state} />
    </footer>
    """
  end

  defp time_bar(assigns) do
    ~H"""
    <div
      x-data="
        {
          position: 0,
          ratio: 0,
          percent: 0,
          time: 0,
          width: 0,
          dragging: false,
          update (x) {
            if (this.width && $store.player.duration.real) {
              this.position = Math.min(x, this.width)
              this.ratio = this.position / this.width
              this.percent = (this.ratio * 100).toFixed(2)
              this.time = this.ratio * $store.player.duration.real
            }
          },
          startDrag (event) {
            if (event.buttons === 1) {
              this.dragging = true
            }
          },
          endDrag () {
            if (this.dragging) {
              this.dragging = false
              mediaPlayer.seekRatio(this.ratio)
              $store.player.progress.percent = this.percent
            }
          }
        }
      "
      x-init="width = $el.clientWidth"
      class="group cursor-pointer h-[32px] -mt-[16px] relative mr-[12px]"
      @resize.window="width = $el.clientWidth"
      @mousemove.window="dragging && update($event.clientX)"
      @mousemove="!dragging && update($event.clientX)"
      @mousedown.prevent="startDrag($event)"
      @mouseup.window="endDrag()"
    >
      <div
        class="absolute border bg-gray-100 border-gray-200 dark:bg-gray-900 dark:border-gray-800 px-1 -top-4 rounded-sm hidden group-hover:block pointer-events-none tabular-nums"
        :class="{ 'hidden': !dragging }"
        :style="position > width / 2 ? `right: ${width - position}px` : `left: ${position}px`"
        x-text="formatTimecode(time)"
      />
      <div class="relative top-[16px] bg-gray-200 dark:bg-gray-800">
        <div
          class="h-[2px] group-hover:h-[4px] bg-lime-500 dark:bg-lime-400"
          :class="{ 'h-[4px]': dragging }"
          style={"width: #{progress_percent(@player_state)}%"}
          :style={
            "$store.player.progress.percent ? `width: ${dragging ? percent : $store.player.progress.percent}%` : 'width: #{progress_percent(@player_state)}%'"
          }
        />
        <div
          class="absolute hidden group-hover:block bg-lime-500 dark:bg-lime-400 rounded-full w-[16px] h-[16px] top-[-6px] pointer-events-none"
          :class="{ 'hidden': !dragging }"
          style="left: calc(0% - 8px)"
          :style="`left: calc(${dragging ? percent : $store.player.progress.percent}% - 8px)`"
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

  defp player_controls(assigns) do
    ~H"""
    <div x-data class="!pt-0 p-4 flex gap-6 items-center text-gray-900 dark:text-gray-100 fill-current">
      <span @click="mediaPlayer.seekRelative(-60)" class="cursor-pointer" title="Back 1 minute">
        <FA.icon name="backward-step" class="w-4 h-4 sm:w-5 sm:h-5" />
      </span>
      <span @click="mediaPlayer.seekRelative(-10)" class="cursor-pointer" title="Back 10 seconds">
        <FA.icon name="rotate-left" class="w-4 h-4 sm:w-5 sm:h-5" />
      </span>
      <span @click="mediaPlayer.playPause()" class="cursor-pointer" title="Play">
        <span :class="{ hidden: $store.player.playing }">
          <FA.icon name="play" class="w-6 h-6 sm:w-7 sm:h-7" />
        </span>
        <span class="hidden" :class="{ hidden: !$store.player.playing }">
          <FA.icon name="pause" class="w-6 h-6 sm:w-7 sm:h-7" />
        </span>
      </span>
      <span @click="mediaPlayer.seekRelative(10)" class="cursor-pointer" title="Forward 10 seconds">
        <FA.icon name="rotate-right" class="w-4 h-4 sm:w-5 sm:h-5" />
      </span>
      <span @click="mediaPlayer.seekRelative(60)" class="cursor-pointer" title="Forward 1 minute">
        <FA.icon name="forward-step" class="w-4 h-4 sm:w-5 sm:h-5" />
      </span>
      <div class="flex-grow text-gray-600 dark:text-gray-500 text-sm sm:text-base">
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
        class="flex gap-2 items-center"
      >
        <div @click="open = !open" class="flex gap-2 items-center cursor-pointer">
          <span class="hidden sm:block text-gray-600 dark:text-gray-500 text-sm sm:text-base">
            <.alpine_value_with_fallback
              alpine_value="$store.player.playbackRate"
              alpine_expression="formatDecimal($store.player.playbackRate)"
              fallback={player_state_playback_rate(@player_state)}
            />x
          </span>
          <FA.icon name="gauge-high" class="w-4 h-4 sm:w-5 sm:h-5" />
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
      :class="{ 'hidden': !open }"
      class="hidden absolute bottom-12 right-4 max-w-80 text-gray-800 dark:text-gray-200 z-50 shadow-md"
    >
      <div class="w-full h-full bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-sm divide-y divide-gray-200 dark:divide-gray-800">
        <div class="p-3">
          <p class="text-center font-bold text-lg sm:text-xl">
            <span x-text="formatDecimal($store.player.playbackRate)" />x
          </p>
        </div>
        <div>
          <div class="flex divide-x divide-gray-200 dark:divide-gray-800">
            <div @click="dec()" class="p-4 flex-grow cursor-pointer hover:bg-gray-300 dark:hover:bg-gray-700">
              <FA.icon name="minus" class="w-4 h-4 sm:w-5 sm:h-5 mx-auto" />
            </div>
            <div @click="inc()" class="p-4 flex-grow cursor-pointer hover:bg-gray-300 dark:hover:bg-gray-700">
              <FA.icon name="plus" class="w-4 h-4 sm:w-5 sm:h-5 mx-auto" />
            </div>
          </div>
        </div>
        <div class="flex py-3 tabular-nums sm:text-lg">
          <span
            @click="mediaPlayer.setPlaybackRate('1.0'); close()"
            class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
          >
            1.0x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('1.25'); close()"
            class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
          >
            1.25x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('1.5'); close()"
            class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
          >
            1.5x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('1.75'); close()"
            class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
          >
            1.75x
          </span>
          <span
            @click="mediaPlayer.setPlaybackRate('2.0'); close()"
            class="px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700 cursor-pointer"
          >
            2.0x
          </span>
        </div>
      </div>
    </div>
    """
  end

  def logo_with_tagline(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <h1 class="flex">
        <.ambry_icon class="w-12 h-12" />
        <.ambry_title class="h-12" />
      </h1>

      <p class="font-semibold text-gray-500 dark:text-gray-400">
        Personal Audiobook Streaming
      </p>
    </div>
    """
  end

  def book_tiles(assigns) do
    assigns =
      assigns
      |> assign_new(:show_load_more, fn -> false end)
      |> assign_new(:load_more, fn -> {false, false} end)

    {load_more, target} = assigns.load_more

    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for {book, number} <- books_with_numbers(@books) do %>
        <div class="text-center">
          <%= if number do %>
            <p class="sm:text-lg font-bold text-gray-900 dark:text-gray-100">Book <%= number %></p>
          <% end %>
          <div class="group">
            <.link link_type="live_redirect" to={Routes.book_show_path(Endpoint, :show, book)}>
              <span class="block aspect-w-10 aspect-h-15">
                <img
                  src={book.image_path}
                  class="
                    w-full h-full
                    object-center object-cover
                    rounded-lg shadow-md
                    border border-gray-200 dark:border-gray-900
                  "
                />
              </span>
            </.link>
            <p class="group-hover:underline sm:text-lg font-bold text-gray-900 dark:text-gray-100">
              <.link link_type="live_redirect" to={Routes.book_show_path(Endpoint, :show, book)}>
                <%= book.title %>
              </.link>
            </p>
          </div>
          <p class="text-sm sm:text-base text-gray-800 dark:text-gray-200">
            by <Amc.people_links people={book.authors} />
          </p>

          <div class="text-xs sm:text-sm text-gray-600 dark:text-gray-400">
            <Amc.series_book_links series_books={book.series_books} />
          </div>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <div class="text-center text-lg">
          <div phx-click={load_more} phx-target={target} class="group">
            <span class="block aspect-w-10 aspect-h-15 cursor-pointer">
              <span class="load-more w-full h-full rounded-lg shadow-md border flex
                bg-gray-200 dark:bg-gray-700
                border-gray-200 dark:border-gray-700
                ">
                <FA.icon name="ellipsis" class="w-12 h-12 fill-current self-center mx-auto" />
              </span>
            </span>
            <p class="group-hover:underline">
              Load more
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp books_with_numbers(books_assign) do
    case books_assign do
      [] -> []
      [%Book{} | _] = books -> Enum.map(books, &{&1, nil})
      [%SeriesBook{} | _] = series_books -> Enum.map(series_books, &{&1.book, &1.book_number})
    end
  end

  def player_state_tiles(assigns) do
    {load_more, target} = assigns.load_more

    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for player_state <- @player_states do %>
        <div class="text-center">
          <div class="group">
            <div class="relative aspect-w-10 aspect-h-15">
              <img
                src={player_state.media.book.image_path}
                class="
                    w-full h-full
                    object-center object-cover
                    rounded-t-lg shadow-md
                    border border-b-0 border-gray-200 dark:border-gray-900
                  "
              />
              <div class="absolute flex">
                <div
                  x-data={"{
                    id: #{player_state.media.id},
                    loaded: false
                  }"}
                  x-effect="$store.player.mediaId == id ? loaded = true : loaded = false"
                  @click={"loaded ? mediaPlayer.playPause() : mediaPlayer.loadAndPlayMedia(#{player_state.media.id})"}
                  class="
                    cursor-pointer
                    self-center mx-auto flex
                    h-16 w-16
                    bg-white dark:bg-black bg-opacity-80 dark:bg-opacity-80
                    group-hover:bg-opacity-100
                    rounded-full shadow-md transition
                    backdrop-blur-sm
                  "
                >
                  <div class="fill-current self-center mx-auto pl-1" :class="{ 'pl-1': !loaded || !$store.player.playing }">
                    <span :class="{ hidden: loaded && $store.player.playing }">
                      <FA.icon name="play" class="w-7 h-7" />
                    </span>
                    <span class="hidden" :class="{ hidden: !loaded || !$store.player.playing }">
                      <FA.icon name="pause" class="w-7 h-7" />
                    </span>
                  </div>
                </div>
              </div>
            </div>
            <div class="bg-gray-300 dark:bg-gray-800 rounded-b-sm overflow-hidden shadow-sm border-x border-gray-200 dark:border-gray-900">
              <div class="bg-lime-500 dark:bg-lime-400 h-1" style={"width: #{progress_percent(player_state)}%;"} />
            </div>
          </div>
          <p class="hover:underline sm:text-lg font-bold text-gray-900 dark:text-gray-100">
            <.link
              link_type="live_redirect"
              label={player_state.media.book.title}
              to={Routes.book_show_path(Endpoint, :show, player_state.media.book)}
            />
          </p>
          <p class="text-sm sm:text-base text-gray-800 dark:text-gray-200">
            by <Amc.people_links people={player_state.media.book.authors} />
          </p>

          <p class="text-sm sm:text-base text-gray-800 dark:text-gray-200">
            Narrated by <Amc.people_links people={player_state.media.narrators} />
            <%= if player_state.media.full_cast do %>
              <span>full cast</span>
            <% end %>
          </p>

          <div class="text-xs sm:text-sm text-gray-600 dark:text-gray-400">
            <Amc.series_book_links series_books={player_state.media.book.series_books} />
          </div>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <div class="text-center text-lg">
          <div phx-click={load_more} phx-target={target} class="group">
            <span class="block aspect-w-10 aspect-h-15 cursor-pointer">
              <span class="load-more w-full h-full rounded-lg shadow-md border flex
                bg-gray-200 dark:bg-gray-700
                border-gray-200 dark:border-gray-700
                ">
                <FA.icon name="ellipsis" class="w-12 h-12 fill-current self-center mx-auto" />
              </span>
            </span>
            <p class="group-hover:underline">
              Load more
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def people_links(assigns) do
    assigns =
      assign_new(assigns, :classes, fn ->
        underline_class =
          if Map.get(assigns, :underline, true) do
            "hover:underline"
          end

        link_class = assigns[:link_class]

        [underline_class, link_class] |> Enum.join(" ") |> String.trim()
      end)

    ~H"""
    <%= for person_ish <- @people do %>
      <.link
        link_type="live_redirect"
        label={person_ish.name}
        to={Routes.person_show_path(Endpoint, :show, person_ish.person_id)}
        class={@classes}
      /><span class="last:hidden">,</span>
    <% end %>
    """
  end

  def series_book_links(assigns) do
    ~H"""
    <%= for series_book <- Enum.sort_by(@series_books, & &1.series.name) do %>
      <p>
        <.link
          link_type="live_redirect"
          to={Routes.series_show_path(Endpoint, :show, series_book.series)}
          class="hover:underline"
        >
          <%= series_book.series.name %> #<%= series_book.book_number %>
        </.link>
      </p>
    <% end %>
    """
  end

  def primary_link(assigns) do
    extra_classes = assigns[:class] || ""
    extra = assigns_to_attributes(assigns, [])

    default_classes =
      "text-lime-500 dark:text-lime-400 hover:text-lime-800 dark:hover:text-lime-600 hover:underline"

    assigns =
      assigns
      |> assign(:extra, extra)
      |> assign(
        :class,
        String.trim("#{default_classes} #{extra_classes}")
      )

    ~H"""
    <.link class={@class} {@extra} />
    """
  end

  def primary_button(assigns) do
    extra_classes = assigns[:class] || ""
    extra = assigns_to_attributes(assigns, [])

    default_classes =
      PetalComponents.Helpers.convert_string_to_one_line(
        """
        text-white dark:text-black
        font-bold
        px-5 py-2
        rounded
        focus:outline-none
        shadow
        transition-colors
        focus:ring-2
        """ <> primary_button_color_classes(assigns[:color] || "lime")
      )

    assigns =
      assigns
      |> assign(:extra, extra)
      |> assign(
        :class,
        String.trim("#{default_classes} #{extra_classes}")
      )

    ~H"""
    <button class={@class} {@extra}>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  defp primary_button_color_classes("lime"),
    do: """
    bg-lime-500 dark:bg-lime-400
    hover:bg-lime-700 dark:hover:bg-lime-600
    focus:ring-lime-300 dark:focus:ring-lime-700
    """

  defp primary_button_color_classes("yellow"),
    do: """
    bg-yellow-500 dark:bg-yellow-400
    hover:bg-yellow-700 dark:hover:bg-yellow-600
    focus:ring-yellow-300 dark:focus:ring-yellow-700
    """

  defp primary_button_color_classes("red"),
    do: """
    bg-red-500 dark:bg-red-400
    hover:bg-red-700 dark:hover:bg-red-600
    focus:ring-red-300 dark:focus:ring-red-700
    """

  def header2(assigns) do
    extra_classes = assigns[:class] || ""
    extra = assigns_to_attributes(assigns, [])

    default_classes = "text-gray-900 dark:text-gray-50"

    assigns =
      assigns
      |> assign(:extra, extra)
      |> assign(
        :class,
        String.trim("#{default_classes} #{extra_classes}")
      )

    ~H"""
    <.h2 class={@class} {@extra}>
      <%= render_slot(@inner_block) %>
    </.h2>
    """
  end

  def form_card(assigns) do
    ~H"""
    <div class="flex flex-col p-10 rounded-lg shadow-lg space-y-6 bg-white dark:bg-gray-900">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
