defmodule AmbryWeb.Components do
  @moduledoc """
  Shared function components used throughout the app.
  """

  use AmbryWeb, :p_component

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  alias AmbryWeb.Components.PlayButton
  alias AmbryWeb.Endpoint
  alias AmbryWeb.Router.Helpers, as: Routes

  def ambry_icon(assigns) do
    extra_classes = assigns[:class] || ""
    default_classes = "text-lime-500 dark:text-lime-400"
    assigns = assign(assigns, :class, String.trim("#{default_classes} #{extra_classes}"))

    ~H"""
    <svg class={@class} version="1.1" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
      <path d="m512 287.9-4e-3 112c-0.896 44.2-35.896 80.1-79.996 80.1-26.47 0-48-21.56-48-48.06v-127.84c0-26.5 21.5-48.1 48-48.1 10.83 0 20.91 2.723 30.3 6.678-12.6-103.58-100.2-182.55-206.3-182.55s-193.71 78.97-206.3 182.57c9.39-4 19.47-6.7 30.3-6.7 26.5 0 48 21.6 48 48.1v127.9c0 26.4-21.5 48-48 48-44.11 0-79.1-35.88-79.1-80.06l-0.9-111.94c0-141.2 114.8-256 256-256 140.9 0 256.5 114.56 256 255.36 0 0.2 0 0-2e-3 0.54451z" fill="currentColor"/>
      <path d="m364 347v-138.86c0-12.782-10.366-23.143-23.143-23.143h-146.57c-25.563 0-46.286 20.723-46.286 46.286v154.29c0 25.563 20.723 46.286 46.286 46.286h154.29c8.5195 0 15.429-6.9091 15.429-14.995 0-5.6507-3.1855-10.376-7.7143-13.066v-39.227c4.725-4.6479 7.7143-10.723 7.7143-17.569zm-147.01-100.29h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143s-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143s3.4714-7.7143 7.2804-7.7143zm0 30.857h92.572c4.6768 0 8.1482 3.4714 8.1482 7.7143 0 4.2429-3.4714 7.7143-7.7143 7.7143h-93.006c-3.8089 0-7.2804-3.4714-7.2804-7.7143 0-4.2429 3.4714-7.7143 7.2804-7.7143zm116.15 123.43h-138.86c-8.5195 0-15.429-6.9091-15.429-15.429 0-8.5195 6.9091-15.429 15.429-15.429h138.86z" fill="currentColor"/>
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
        <path d="m283.08 388.31h-123.38l-24 91.692h-95.692l140-448h82.769l140.92 448h-96.615zm-103.69-75.385h83.692l-41.846-159.69z"/>
        <g>
          <path d="m533.4 146.87 62.92 240.93 62.691-240.93h87.859v333.13h-67.496v-90.147l6.1776-138.88-66.581 229.03h-45.76l-66.581-229.03 6.1775 138.88v90.147h-67.267v-333.13z"/>
          <path d="m800.87 480v-333.13h102.96q52.166 0 79.165 23.338 27.227 23.109 27.227 67.953 0 25.397-11.211 43.701-11.211 18.304-30.659 26.77 22.422 6.4064 34.549 25.854 12.126 19.219 12.126 47.59 0 48.506-26.77 73.216-26.541 24.71-77.105 24.71zm67.267-144.83v89.003h43.014q18.075 0 27.456-11.211 9.3809-11.211 9.3809-31.803 0-44.845-32.49-45.989zm0-48.963h35.006q39.582 0 39.582-40.955 0-22.651-9.152-32.49t-29.744-9.8384h-35.693z"/>
          <path d="m1164.7 358.28h-33.405v121.72h-67.267v-333.13h107.31q50.565 0 78.02 26.312 27.685 26.083 27.685 74.36 0 66.352-48.277 92.893l58.344 136.36v3.2032h-72.301zm-33.405-56.056h38.21q20.134 0 30.202-13.27 10.067-13.499 10.067-35.922 0-50.107-39.125-50.107h-39.354z"/>
          <path d="m1412.7 296.5 50.107-149.63h73.216l-89.232 212.33v120.81h-68.182v-120.81l-89.461-212.33h73.216z"/>
        </g>
      </g>
    </svg>
    """
  end

  def play_icon(assigns) do
    ~H"""
    <svg class={@class} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
      <path fill="currentColor" d="M512 256C512 397.4 397.4 512 256 512C114.6 512 0 397.4 0 256C0 114.6 114.6 0 256 0C397.4 0 512 114.6 512 256zM176 168V344C176 352.7 180.7 360.7 188.3 364.9C195.8 369.2 205.1 369 212.5 364.5L356.5 276.5C363.6 272.1 368 264.4 368 256C368 247.6 363.6 239.9 356.5 235.5L212.5 147.5C205.1 142.1 195.8 142.8 188.3 147.1C180.7 151.3 176 159.3 176 168V168z"/>
    </svg>
    """
  end

  def book_icon(assigns) do
    ~H"""
    <svg class={@class} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512">
      <path fill="currentColor" d="M144.3 32.04C106.9 31.29 63.7 41.44 18.6 61.29c-11.42 5.026-18.6 16.67-18.6 29.15l0 357.6c0 11.55 11.99 19.55 22.45 14.65c126.3-59.14 219.8 11 223.8 14.01C249.1 478.9 252.5 480 256 480c12.4 0 16-11.38 16-15.98V80.04c0-5.203-2.531-10.08-6.781-13.08C263.3 65.58 216.7 33.35 144.3 32.04zM557.4 61.29c-45.11-19.79-88.48-29.61-125.7-29.26c-72.44 1.312-118.1 33.55-120.9 34.92C306.5 69.96 304 74.83 304 80.04v383.1C304 468.4 307.5 480 320 480c3.484 0 6.938-1.125 9.781-3.328c3.925-3.018 97.44-73.16 223.8-14c10.46 4.896 22.45-3.105 22.45-14.65l.0001-357.6C575.1 77.97 568.8 66.31 557.4 61.29z"/>
    </svg>
    """
  end

  def search_icon(assigns) do
    ~H"""
    <svg class={@class} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
      <path fill="currentColor" d="M500.3 443.7l-119.7-119.7c27.22-40.41 40.65-90.9 33.46-144.7C401.8 87.79 326.8 13.32 235.2 1.723C99.01-15.51-15.51 99.01 1.724 235.2c11.6 91.64 86.08 166.7 177.6 178.9c53.8 7.189 104.3-6.236 144.7-33.46l119.7 119.7c15.62 15.62 40.95 15.62 56.57 0C515.9 484.7 515.9 459.3 500.3 443.7zM79.1 208c0-70.58 57.42-128 128-128s128 57.42 128 128c0 70.58-57.42 128-128 128S79.1 278.6 79.1 208z"/>
    </svg>
    """
  end

  def header(assigns) do
    ~H"""
    <div class="p-4 flex text-gray-600 dark:text-gray-500">
      <div class="flex-1">
        <.link link_type="live_redirect" to="/" class="flex">
          <.ambry_icon class="mt-1 h-6 lg:h-7" />
          <.ambry_title class="mt-1 h-6 lg:h-7 hidden md:block" />
        </.link>
      </div>
      <div class="flex-1">
        <div class="flex justify-center gap-8 lg:gap-12">
          <.link link_type="live_redirect" to="/" class={nav_class(@active_path == "/")}>
            <.play_icon class="mt-1 h-6 lg:h-7 lg:hidden" />
            <p class="hidden lg:block font-bold text-xl">Now Playing</p>
          </.link>
          <.link link_type="live_redirect" to="/" class={nav_class(@active_path == "/library")}>
            <.book_icon class="mt-1 lg:hidden w-6 h-6" />
            <p class="hidden lg:block font-bold text-xl">Library</p>
          </.link>
          <.link link_type="live_redirect" to="/" class={nav_class(false, "flex content-center gap-4")}>
            <.search_icon class="mt-1 w-6 h-6" />
            <p class="hidden xl:block font-bold text-xl">Search</p>
          </.link>
        </div>
      </div>
      <div class="flex-1">
        <div class="flex">
          <div class="flex-grow" />
          <img class="mt-1 h-6 lg:h-7 rounded-full cursor-pointer" src={gravatar_url(@user.email)} />
        </div>
      </div>
    </div>
    """
  end

  defp nav_class(active?, extra \\ "")
  defp nav_class(true, extra), do: "text-gray-900 dark:text-gray-100 #{extra}"
  defp nav_class(false, extra), do: "hover:text-gray-900 dark:hover:text-gray-100 #{extra}"

  def logo_with_tagline(assigns) do
    ~H"""
    <h1 class="text-center">
      <img class="mx-auto block dark:hidden" style="max-height: 128px;" alt="Ambry" src={Routes.static_path(Endpoint, "/images/logo_256x1056.svg")}>
      <img class="mx-auto hidden dark:block" style="max-height: 128px;" alt="Ambry" src={Routes.static_path(Endpoint, "/images/logo_dark_256x1056.svg")}>
      <span class="font-semibold text-gray-500 dark:text-gray-400">Personal Audiobook Streaming</span>
    </h1>
    """
  end

  # prop books, :list, required: true
  # prop show_load_more, :boolean, default: false
  # prop load_more, :event

  def book_tiles(assigns) do
    assigns =
      assigns
      |> assign_new(:show_load_more, fn -> false end)
      |> assign_new(:load_more, fn -> {false, false} end)

    {load_more, target} = assigns.load_more

    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for {book, number} <- books_with_numbers(@books) do %>
        <div class="text-center text-lg">
          <%= if number do %>
            <p>Book <%= number %></p>
          <% end %>
          <div class="group">
            <.link link_type="live_redirect" to={Routes.book_show_path(Endpoint, :show, book)}>
              <span class="block aspect-w-10 aspect-h-15">
                <img
                  src={book.image_path}
                  class="w-full h-full object-center object-cover rounded-lg shadow-md border border-gray-200 filter group-hover:saturate-200 group-hover:shadow-lg group-hover:-translate-y-1 transition"
                />
              </span>
            </.link>
            <p class="group-hover:underline">
              <.link link_type="live_redirect" to={Routes.book_show_path(Endpoint, :show, book)}>
                <%= book.title %>
              </.link>
            </p>
          </div>
          <p class="text-gray-500">
            by <Amc.people_links people={book.authors} />
          </p>

          <div class="text-sm text-gray-400">
            <Amc.series_book_links series_books={book.series_books} />
          </div>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <div class="text-center text-lg">
          <div phx-click={load_more}, phx-target={target} class="group">
            <span class="block aspect-w-10 aspect-h-15 cursor-pointer">
              <span class="load-more bg-gray-200 w-full h-full rounded-lg shadow-md border border-gray-200 group-hover:shadow-lg group-hover:-translate-y-1 transition flex">
                <Heroicons.Outline.dots_horizontal class="self-center mx-auto h-12 w-12" />
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

  # prop player_states, :list
  # prop show_load_more, :boolean, default: false
  # prop load_more, :event
  # prop user, :any, required: true
  # prop browser_id, :string, required: true

  def player_state_tiles(assigns) do
    {load_more, target} = assigns.load_more

    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for player_state <- @player_states do %>
        <div class="text-center text-lg">
          <div class="group">
            <span class="relative block aspect-w-10 aspect-h-15">
              <img
                src={player_state.media.book.image_path}
                class="w-full h-full object-center object-cover rounded-t-lg shadow-md border border-b-0 border-gray-200 filter group-hover:saturate-200"
              />
              <span class="absolute flex">
                <span class="self-center mx-auto h-20 w-20 bg-white bg-opacity-80 group-hover:bg-opacity-100 backdrop-blur-sm rounded-full shadow-md flex group-hover:-translate-y-1 group-hover:shadow-lg transition">
                  <span style="height: 50px;" class="block self-center mx-auto">
                    <.live_component
                      module={PlayButton}
                      id={player_state.media.id}
                      media={player_state.media}
                      user={@user}
                      browser_id={@browser_id}
                    />
                  </span>
                </span>
              </span>
            </span>
            <div class="bg-gray-200 rounded-b-full overflow-hidden shadow-sm">
              <div class="bg-lime-500 h-2" style={"width: #{progress_percent(player_state)}%;"} />
            </div>
          </div>
          <p class="hover:underline">
            <.link
              link_type="live_redirect"
              label={player_state.media.book.title}
              to={Routes.book_show_path(Endpoint, :show, player_state.media.book)}
            />
          </p>
          <p class="text-gray-500">
            by <Amc.people_links people={player_state.media.book.authors} />
          </p>

          <p class="text-gray-500 text-sm">
            Narrated by <Amc.people_links people={player_state.media.narrators} />
            <%= if player_state.media.full_cast do %>
              <span>full cast</span>
            <% end %>
          </p>

          <div class="text-sm text-gray-400">
            <Amc.series_book_links series_books={player_state.media.book.series_books} />
          </div>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <div class="text-center text-lg">
          <div phx-click={load_more} phx-target={target} class="group">
            <span class="block aspect-w-10 aspect-h-15 cursor-pointer">
              <span class="load-more bg-gray-200 w-full h-full rounded-lg shadow-md border border-gray-200 group-hover:shadow-lg group-hover:-translate-y-1 transition flex">
                <Heroicons.Outline.dots_horizontal class="self-center mx-auto h-12 w-12" />
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

  defp progress_percent(%{position: position, media: %{duration: duration}}) do
    position
    |> Decimal.div(duration)
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  # prop :people, :list, required: true
  # prop :underline, :boolean, default: true
  # prop :link_class, :string

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

  # prop :series_books, :list, required: true

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
      """
      bg-lime-500 dark:bg-lime-400
      text-white dark:text-black
      font-bold
      px-5 py-2
      rounded
      focus:outline-none
      shadow
      hover:bg-lime-700 dark:hover:bg-lime-600
      transition-colors
      focus:ring-2
      focus:ring-lime-300 dark:focus:ring-lime-700
      """
      |> PetalComponents.Helpers.convert_string_to_one_line()

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
