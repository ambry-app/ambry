defmodule AmbryWeb.Layouts do
  @moduledoc false

  use AmbryWeb, :html

  import AmbryWeb.Gravatar
  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias Ambry.Media
  alias AmbryWeb.Components.SearchBox

  embed_templates "layouts/*"

  @doc """
  Main app navigation header
  """
  def nav_header(assigns) do
    ~H"""
    <header id="nav-header" class="border-zinc-100 dark:border-zinc-900">
      <div class="flex p-4 text-zinc-600 dark:text-zinc-500">
        <div class="flex-1">
          <.link navigate={~p"/"} class="flex">
            <.ambry_icon class="mt-1 h-6 w-6 lg:h-7 lg:w-7" />
            <.ambry_title class="mt-1 hidden h-6 md:block lg:h-7" />
          </.link>
        </div>
        <div class="flex-1">
          <div class="flex justify-center gap-8 lg:gap-12">
            <.link navigate={~p"/"} class={nav_class(@active_path == "/")}>
              <span title="Now playing"><FA.icon name="circle-play" class="mt-1 h-6 w-6 fill-current lg:hidden" /></span>
              <span class="hidden text-xl font-bold lg:block">Now Playing</span>
            </.link>
            <.link navigate={~p"/library"} class={nav_class(@active_path == "/library")}>
              <span title="Library"><FA.icon name="book-open" class="mt-1 h-6 w-6 fill-current lg:hidden" /></span>
              <span class="hidden text-xl font-bold lg:block">Library</span>
            </.link>
            <span
              phx-click={show_search()}
              class={nav_class(String.starts_with?(@active_path, "/search"), "flex content-center gap-4 cursor-pointer")}
            >
              <span title="Search">
                <FA.icon name="magnifying-glass" class="mt-1 h-6 w-6 fill-current lg:h-5 lg:w-5" />
              </span>
              <span class="hidden text-xl font-bold xl:block">Search</span>
            </span>
          </div>
        </div>
        <div class="flex-1">
          <div class="flex">
            <div class="grow" />
            <div phx-click-away={hide_menu("user-menu")} phx-window-keydown={hide_menu("user-menu")} phx-key="escape">
              <img
                phx-click={toggle_menu("user-menu")}
                class="mt-1 h-6 cursor-pointer rounded-full lg:h-7 lg:w-7"
                src={gravatar_url(@user.email)}
              />
              <.user_menu user={@user} />
            </div>
          </div>
        </div>
      </div>

      <.live_component module={SearchBox} id="search-box" path={@active_path} hide_search={hide_search()} />
    </header>
    """
  end

  def ambry_icon(assigns) do
    extra_classes = assigns[:class] || ""
    default_classes = "text-brand dark:text-brand-dark"
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
    default_classes = "text-zinc-900 dark:text-zinc-100"
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

  defp nav_class(active?, extra \\ "")
  defp nav_class(true, extra), do: "text-zinc-900 dark:text-zinc-100 #{extra}"
  defp nav_class(false, extra), do: "hover:text-zinc-900 dark:hover:text-zinc-100 #{extra}"

  defp user_menu(assigns) do
    ~H"""
    <.menu_wrapper id="user-menu" user={@user}>
      <div class="py-3">
        <%= if @user.admin do %>
          <.link navigate={~p"/admin"} class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700">
            <FA.icon name="screwdriver-wrench" class="h-5 w-5 fill-current" />
            <p>Admin</p>
          </.link>
        <% end %>
        <.link
          navigate={~p"/users/settings"}
          class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
        >
          <FA.icon name="user-gear" class="h-5 w-5 fill-current" />
          <p>Account Settings</p>
        </.link>
        <.link
          href={~p"/users/log_out"}
          method="delete"
          class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700"
        >
          <FA.icon name="arrow-right-from-bracket" class="h-5 w-5 fill-current" />
          <p>Log out</p>
        </.link>
      </div>
    </.menu_wrapper>
    """
  end

  def footer(assigns) do
    ~H"""
    <footer class="relative bg-zinc-100 dark:bg-zinc-900">
      <.time_bar :if={@player.player_state} player_state={@player.player_state} />
      <.player_controls
        :if={@player.player_state}
        playback_state={@player.playback_state}
        player_state={@player.player_state}
      />
      <.media_player player_state={@player.player_state} />
    </footer>
    """
  end

  defp media_player(assigns) do
    ~H"""
    <div id="media-player" phx-hook="media-player" {player_state_attrs(@player_state)}>
      <audio />
    </div>
    """
  end

  defp player_state_attrs(nil), do: %{"data-media-unloaded" => true}

  defp player_state_attrs(%Media.PlayerState{
         media: %Media.Media{id: id, mpd_path: path, hls_path: hls_path},
         position: position,
         playback_rate: playback_rate
       }) do
    %{
      "data-media-id" => id,
      "data-media-position" => position,
      "data-media-path" => "#{path}#t=#{position}",
      "data-media-hls-path" => "#{hls_path}#t=#{position}",
      "data-media-playback-rate" => playback_rate
    }
  end

  # these comments are here for the tailwind JIT:
  # when hovering we need class="h-[4px]" on the progress bar and class="!block"
  # on the handle
  defp time_bar(assigns) do
    ~H"""
    <div
      id="time-bar"
      class="group absolute -top-4 h-8 w-full cursor-pointer"
      phx-hook="time-bar"
      data-duration={@player_state.media.duration}
    >
      <div
        id="time-code"
        phx-update="ignore"
        class="pointer-events-none absolute -top-4 hidden rounded-sm border border-zinc-200 bg-zinc-100 px-1 tabular-nums group-hover:block dark:border-zinc-800 dark:bg-zinc-900"
      />
      <div class="mr-[12px] relative top-4 bg-zinc-200 dark:bg-zinc-800">
        <div
          class="h-[2px] bg-brand group-hover:h-[4px] dark:bg-brand-dark"
          style={"width: #{progress_percent(@player_state)}%"}
        />
        <div
          class="top-[-6px] bg-brand pointer-events-none absolute hidden h-4 w-4 rounded-full group-hover:!block dark:bg-brand-dark"
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

  defp player_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-6 fill-current p-4 text-zinc-900 dark:text-zinc-100">
      <.player_button action={seek_relative(-60)} title="Back 1 minute" icon="backward-step" />
      <.player_button action={seek_relative(-10)} title="Back 10 seconds" icon="rotate-left" />
      <.play_pause_button playback_state={@playback_state} />
      <.player_button action={seek_relative(10)} title="Forward 10 seconds" icon="rotate-right" />
      <.player_button action={seek_relative(60)} title="Forward 1 minute" icon="forward-step" />

      <div class="whitespace-nowrap text-sm tabular-nums text-zinc-600 dark:text-zinc-500 sm:text-base">
        <span><%= player_state_progress(@player_state) %></span>
        <span class="hidden sm:inline">/</span>
        <span><%= player_state_duration(@player_state) %></span>
      </div>
      <div class="grow overflow-hidden text-ellipsis whitespace-nowrap">
        <span class="text-sm text-zinc-800 dark:text-zinc-300 sm:text-base">
          <.link navigate={~p"/books/#{@player_state.media.book}"} class="hover:underline" phx-no-format>
          <%= @player_state.media.book.title %></.link> •
          <span>by <.people_links people={@player_state.media.book.authors} /></span>
          • narrated by <span><.people_links people={@player_state.media.narrators} /></span>
        </span>
      </div>
      <div
        title="Playback speed"
        class="flex items-center gap-2"
        phx-click-away={hide_menu("playback-rate-menu")}
        phx-window-keydown={hide_menu("playback-rate-menu")}
        phx-key="escape"
      >
        <div phx-click={toggle_menu("playback-rate-menu")} class="flex cursor-pointer items-center gap-2">
          <span class="hidden text-sm text-zinc-600 dark:text-zinc-500 sm:block sm:text-base">
            <%= player_state_playback_rate(@player_state) %>x
          </span>
          <FA.icon name="gauge-high" class="h-4 w-4 sm:h-5 sm:w-5" />
        </div>
        <.playback_rate_menu player_state={@player_state} />
      </div>
    </div>
    """
  end

  attr :action, JS, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :class, :string, default: "h-4 w-4 sm:h-5 sm:w-5"

  defp player_button(assigns) do
    ~H"""
    <span phx-click={@action} class="cursor-pointer" title={@title}>
      <FA.icon name={@icon} class={@class} />
    </span>
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

  attr :playback_state, :atom, required: true

  defp play_pause_button(assigns) do
    ~H"""
    <span phx-click={toggle_playback()} class="cursor-pointer">
      <span :if={@playback_state == :paused} title="Play">
        <FA.icon name="play" class="h-6 w-6 pl-1 sm:h-7 sm:w-7" />
      </span>
      <span :if={@playback_state == :playing} title="Pause">
        <FA.icon name="pause" class="h-6 w-6 sm:h-7 sm:w-7" />
      </span>
    </span>
    """
  end

  defp playback_rate_menu(assigns) do
    ~H"""
    <div
      id="playback-rate-menu"
      class="max-w-80 absolute right-4 bottom-12 z-50 hidden text-zinc-800 shadow-md dark:text-zinc-200"
    >
      <div class="h-full w-full divide-y divide-zinc-200 rounded-sm border border-zinc-200 bg-zinc-50 dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900">
        <div class="p-3">
          <p class="text-center text-lg font-bold sm:text-xl">
            <%= player_state_playback_rate(@player_state) %>x
          </p>
        </div>
        <div>
          <div class="flex divide-x divide-zinc-200 dark:divide-zinc-800">
            <.adjust_playback_rate_button action={decrement_playback_rate()} icon="minus" />
            <.adjust_playback_rate_button action={increment_playback_rate()} icon="plus" />
          </div>
        </div>
        <div class="flex py-3 tabular-nums sm:text-lg">
          <.set_playback_rate_button rate="1.0" />
          <.set_playback_rate_button rate="1.25" />
          <.set_playback_rate_button rate="1.5" />
          <.set_playback_rate_button rate="1.75" />
          <.set_playback_rate_button rate="2.0" />
        </div>
      </div>
    </div>
    """
  end

  attr :action, JS, required: true
  attr :icon, :string, required: true

  defp adjust_playback_rate_button(assigns) do
    ~H"""
    <div phx-click={@action} class="grow cursor-pointer p-4 hover:bg-zinc-300 dark:hover:bg-zinc-700">
      <FA.icon name={@icon} class="mx-auto h-4 w-4 sm:h-5 sm:w-5" />
    </div>
    """
  end

  attr :rate, :string, required: true

  defp set_playback_rate_button(assigns) do
    ~H"""
    <span phx-click={set_playback_rate(@rate)} class="cursor-pointer px-4 py-2 hover:bg-zinc-300 dark:hover:bg-zinc-700">
      <%= @rate %>x
    </span>
    """
  end

  ## JS Commands

  defp show_search(js \\ %JS{}) do
    js
    |> JS.show(
      to: "#search-box",
      time: 100,
      transition: transition_in()
    )
    |> JS.focus(to: "#search-input")
    |> JS.dispatch("ambry:search-box-shown", to: "#search-box")
  end

  defp hide_search(js \\ %JS{}) do
    js
    |> JS.hide(
      to: "#search-box",
      time: 100,
      transition: transition_out()
    )
    |> JS.dispatch("ambry:search-box-hidden", to: "#search-box")
  end

  defp toggle_playback, do: JS.dispatch("ambry:toggle-playback", to: "#media-player")

  defp seek_relative(value), do: JS.dispatch("ambry:seek-relative", to: "#media-player", detail: %{value: value})

  defp decrement_playback_rate, do: JS.dispatch("ambry:decrement-playback-rate", to: "#media-player")

  defp increment_playback_rate, do: JS.dispatch("ambry:increment-playback-rate", to: "#media-player")

  defp set_playback_rate(value), do: JS.dispatch("ambry:set-playback-rate", to: "#media-player", detail: %{value: value})
end
