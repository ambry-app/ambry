defmodule AmbryWeb.NowPlayingLive.Index.Components do
  @moduledoc """
  NowPlaying LiveView components.
  """

  use AmbryWeb, :html

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias AmbryWeb.NowPlayingLive.Index.Bookmarks

  alias AmbryWeb.Endpoint
  alias AmbryWeb.Router.Helpers, as: Routes

  def media_details(assigns) do
    ~H"""
    <div class="flex-none lg:basis-7/12 lg:flex lg:place-items-center lg:place-content-center">
      <div class="m-8 flex space-x-4 sm:m-12 md:space-x-8 lg:mr-4">
        <img
          src={@media.book.image_path}
          class="h-52 rounded-lg border border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900 sm:h-64 md:h-72 lg:h-80 xl:h-96 2xl:h-[36rem]"
        />

        <div class="pt-4 md:pt-6 lg:pt-8">
          <h1 class="text-2xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-3xl xl:text-4xl">
            <.link
              link_type="live_redirect"
              label={@media.book.title}
              to={Routes.book_show_path(Endpoint, :show, @media.book)}
              class="hover:underline"
            />
          </h1>

          <p class="pb-4 text-zinc-800 dark:text-zinc-200 sm:text-lg xl:text-xl">
            <span>by <Amc.people_links people={@media.book.authors} /></span>
          </p>

          <p class="pb-4 text-zinc-800 dark:text-zinc-200 sm:text-lg">
            <span>
              Narrated by <Amc.people_links people={@media.narrators} />
              <%= if @media.full_cast do %>
                <span>full cast</span>
              <% end %>
            </span>
          </p>

          <div class="text-sm text-zinc-600 dark:text-zinc-400 sm:text-base">
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
        flex-grow lg:flex-1 lg:basis-5/12 flex flex-col xl:max-w-2xl
        overflow-hidden lg:overflow-y-auto
        mx-0 sm:mx-8 lg:mx-16 mt-4 lg:mt-16 lg:ml-4
        text-zinc-600 dark:text-zinc-500
      "
    >
      <div class="flex">
        <.media_tab name="chapters" label="Chapters" />
        <.media_tab name="bookmarks" label="Bookmarks" />
        <.media_tab name="about" label="About" />
      </div>

      <div class="flex-1 overflow-y-auto text-zinc-700 dark:text-zinc-300">
        <%!-- <div class="hidden" :class="{ hidden: tab !== 'chapters' }">
          <.chapters chapters={@media.chapters} />
        </div> --%>

        <%!-- <div class="hidden" :class="{ hidden: tab !== 'bookmarks' }">
          <.live_component id="bookmarks" module={Bookmarks} media={@media} user={@user} />
        </div> --%>

        <%!-- <div class="hidden" :class="{ hidden: tab !== 'about' }">
          <.about book={@media.book} />
        </div> --%>
      </div>
    </div>
    """
  end

  defp media_tab(assigns) do
    ~H"""
    <%!-- <span
      @click={"tab = '#{@name}'"}
      class="flex-1 cursor-pointer border-b border-zinc-200 pb-3 text-center font-medium uppercase hover:text-zinc-900 dark:border-zinc-900 dark:hover:text-zinc-100"
      :class={"
        tab === '#{@name}' &&
          'text-zinc-900 dark:text-zinc-100 !border-b-2 !border-brand dark:!border-brand-dark'
      "}
    >
      <%= @label %>
    </span> --%>
    """
  end

  def chapters(assigns) do
    ~H"""
    <%= if @chapters == [] do %>
      <p class="p-4 text-center font-semibold text-zinc-800 dark:text-zinc-200">
        This book has no chapters defined.
      </p>
    <% else %>
      <table class="w-full">
        <%= for {chapter, id} <- Enum.with_index(@chapters) do %>
          <%!-- <tr
            class="cursor-pointer"
            :class={"$store.player.currentChapter?.id === #{id} ? 'bg-zinc-50 dark:bg-zinc-900' : ''"}
            @click={"mediaPlayer.seek(#{chapter.time})"}
            x-effect={"
            if ($store.player.currentChapter?.id === #{id}) {
              $el.scrollIntoView({block: 'center'})
            }
            "}
          >
            <td class="flex items-center space-x-2 border-b border-zinc-100 py-4 pl-4 dark:border-zinc-900">
              <div class="invisible flex-none" :class={"{invisible: $store.player.currentChapter?.id !== #{id}}"}>
                <FA.icon name="volume-high" class="h-5 w-5 fill-current" />
              </div>
              <p><%= chapter.title %></p>
            </td>

            <td class="border-b border-zinc-100 py-4 pr-4 text-right tabular-nums dark:border-zinc-900">
              <%= format_timecode(chapter.time) %>
            </td>
          </tr> --%>
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
