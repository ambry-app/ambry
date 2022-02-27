defmodule AmbryWeb.PlayerLive.Player.Components do
  @moduledoc """
  Player LiveView components.
  """

  use AmbryWeb, :p_component

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias AmbryWeb.PlayerLive.Player.Bookmarks

  alias AmbryWeb.Endpoint
  alias AmbryWeb.Router.Helpers, as: Routes

  def media_details(assigns) do
    ~H"""
    <div class="flex-none lg:basis-7/12">
      <div class="flex space-x-4 md:space-x-8 m-8 sm:m-12 lg:m-16 lg:mr-4 lg:flex-1">
        <img
          src={@media.book.image_path}
          class="h-52 sm:h-64 md:h-72 lg:h-80 xl:h-96 object-center object-cover rounded-lg shadow-md"
        />

        <div class="pt-4 md:pt-6 lg:pt-8">
          <h1 class="font-bold text-2xl sm:text-3xl xl:text-4xl text-gray-900 dark:text-gray-100">
            <.link
              link_type="live_redirect"
              label={@media.book.title}
              to={Routes.book_show_path(Endpoint, :show, @media.book)}
              class="hover:underline"
            />
          </h1>

          <p class="pb-4 sm:text-lg xl:text-xl text-gray-800 dark:text-gray-200">
            <span>by <Amc.people_links people={@media.book.authors} /></span>
          </p>

          <p class="pb-4 sm:text-lg text-gray-800 dark:text-gray-200">
            <span>
              Narrated by <Amc.people_links people={@media.narrators} />
              <%= if @media.full_cast do %>
                <span>full cast</span>
              <% end %>
            </span>
          </p>

          <div class="text-sm sm:text-base text-gray-600 dark:text-gray-400">
            <Amc.series_book_links series_books={@media.book.series_books} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def media_tabs(assigns) do
    ~H"""
    <div
      x-data="{ tab: 'chapters' }"
      class="
        flex-grow lg:flex-1 lg:basis-5/12 flex flex-col
        overflow-hidden lg:overflow-auto
        mx-0 sm:mx-8 lg:mx-16 mt-4 lg:mt-16 lg:ml-4
        text-gray-600 dark:text-gray-500
      "
    >
      <div class="flex">
        <.media_tab name="chapters" label="Chapters" />
        <.media_tab name="bookmarks" label="Bookmarks" />
        <.media_tab name="about" label="About" />
      </div>

      <div class="flex-1 overflow-y-auto text-gray-700 dark:text-gray-300">
        <div class="hidden" :class="{ hidden: tab !== 'chapters' }">
          <.chapters chapters={@media.chapters} />
        </div>

        <div class="hidden" :class="{ hidden: tab !== 'bookmarks' }">
          <.live_component
            id="bookmarks"
            module={Bookmarks}
            media={@media}
            user={@user}
          />
        </div>

        <div class="hidden" :class="{ hidden: tab !== 'about' }">
          <.about book={@media.book} />
        </div>
      </div>
    </div>
    """
  end

  defp media_tab(assigns) do
    ~H"""
    <.link
      to="#"
      @click.prevent={"tab = '#{@name}'"}
      class="
        flex-1 pb-3
        uppercase font-medium text-center
        border-b border-gray-200 dark:border-gray-900
        hover:text-gray-900 dark:hover:text-gray-100
      "
      :class={"
        tab === '#{@name}' &&
          'text-gray-900 dark:text-gray-100 !border-b-2 !border-lime-500 dark:!border-lime-400'
      "}
    >
      <%= @label %>
    </.link>
    """
  end

  def chapters(assigns) do
    ~H"""
    <%= if @chapters == [] do %>
      <p class="p-4 font-semibold text-gray-800 dark:text-gray-200">
        This book has no chapters defined.
      </p>
    <% else %>
      <table class="w-full">
        <%= for chapter <- @chapters do %>
          <tr class={"cursor-pointer" <> if chapter.title == "Helena - October 22 2007", do: " bg-gray-200 dark:bg-gray-900", else: ""}>
            <td class="pl-4 py-4 border-b border-gray-100 dark:border-gray-900 flex items-center space-x-2">
              <%= if chapter.title == "Helena - October 22 2007" do %>
                <FA.icon name="volume-high" class="w-5 h-5 fill-current flex-none" />
              <% else %>
                <div class="w-5 h-5 flex-none" />
              <% end %>
              <p><%= chapter.title %></p>
            </td>

            <td class="pr-4 py-4 border-b border-gray-100 dark:border-gray-900 text-right tabular-nums">
              <%= format_timecode(chapter.time) %>
            </td>
          </tr>
        <% end %>
      </table>
    <% end %>
    """
  end

  def about(assigns) do
    ~H"""
    <%= if @book.description do %>
      <div class="markdown p-4">
        <%= raw(Earmark.as_html!(@book.description)) %>
      </div>
    <% end %>
    """
  end
end
