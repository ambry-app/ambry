defmodule AmbryWeb.NowPlayingLive.Index.Components do
  @moduledoc """
  Components for the "now playing" live page.
  """

  use AmbryWeb, :html

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias Ambry.Accounts.User
  alias Ambry.Media

  alias AmbryWeb.NowPlayingLive.Index.Bookmarks

  attr :media, Media.Media, required: true

  def media_details(assigns) do
    ~H"""
    <div class="flex-none lg:flex lg:basis-7/12 lg:place-content-center lg:place-items-center">
      <div class="m-8 flex space-x-4 sm:m-12 md:space-x-8 lg:mr-4">
        <img
          src={@media.book.image_path}
          class="h-52 rounded-lg border border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900 sm:h-64 md:h-72 lg:h-80 xl:h-96 2xl:h-[36rem]"
        />

        <div class="pt-4 md:pt-6 lg:pt-8">
          <h1 class="text-2xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-3xl xl:text-4xl">
            <.link navigate={~p"/books/#{@media.book}"} class="hover:underline"><%= @media.book.title %></.link>
          </h1>

          <p class="pb-4 text-zinc-800 dark:text-zinc-200 sm:text-lg xl:text-xl">
            <span>by <.people_links people={@media.book.authors} /></span>
          </p>

          <p class="pb-4 text-zinc-800 dark:text-zinc-200 sm:text-lg">
            <span>
              Narrated by <.people_links people={@media.narrators} />
              <%= if @media.full_cast do %>
                <span>full cast</span>
              <% end %>
            </span>
          </p>

          <div class="text-sm text-zinc-600 dark:text-zinc-400 sm:text-base">
            <.series_book_links series_books={@media.book.series_books} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :media, Media.Media, required: true
  attr :user, User, required: true

  def media_tabs(assigns) do
    ~H"""
    <div class="mx-0 mt-4 flex grow flex-col overflow-hidden text-zinc-600 dark:text-zinc-500 sm:mx-8 lg:mx-16 lg:mt-16 lg:ml-4 lg:flex-1 lg:basis-5/12 lg:overflow-y-auto xl:max-w-2xl">
      <div class="flex">
        <.media_tab id="chapters" label="Chapters" active={true} />
        <.media_tab id="bookmarks" label="Bookmarks" />
        <.media_tab id="about" label="About" />
      </div>

      <div class="flex-1 overflow-y-auto text-zinc-700 dark:text-zinc-300">
        <div id="chapters-body" class="media-tab-body">
          <.chapters chapters={@media.chapters} />
        </div>

        <div id="bookmarks-body" class="media-tab-body hidden">
          <.live_component id="bookmarks" module={Bookmarks} media={@media} user={@user} />
        </div>

        <div id="about-body" class="media-tab-body hidden">
          <.markdown :if={@media.book.description} content={@media.book.description} class="p-4" />
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp media_tab(assigns) do
    ~H"""
    <span id={@id} phx-click={activate_tab(@id)} class={media_tab_classes(@active)}>
      <%= @label %>
    </span>
    """
  end

  defp media_tab_classes(false),
    do:
      "media-tab flex-1 cursor-pointer border-b border-zinc-200 pb-3 text-center font-medium uppercase hover:text-zinc-900 dark:border-zinc-900 dark:hover:text-zinc-100"

  defp media_tab_classes(true),
    do:
      "media-tab border-brand flex-1 cursor-pointer border-b-2 pb-3 text-center font-medium uppercase text-zinc-900 dark:border-brand-dark dark:text-zinc-100"

  defp activate_tab(js \\ %JS{}, id) do
    js
    |> JS.set_attribute({"class", media_tab_classes(false)}, to: ".media-tab")
    |> JS.set_attribute({"class", media_tab_classes(true)}, to: "##{id}")
    |> JS.add_class("hidden", to: ".media-tab-body")
    |> JS.remove_class("hidden", to: "##{id}-body")
  end

  attr :chapters, :list, required: true

  defp chapters(assigns) do
    ~H"""
    <%= if @chapters == [] do %>
      <p class="p-4 text-center font-semibold text-zinc-800 dark:text-zinc-200">
        This book has no chapters defined.
      </p>
    <% else %>
      <table class="w-full">
        <%= for {chapter, id} <- Enum.with_index(@chapters) do %>
          <tr
            class="cursor-pointer"
            x-class={"$store.player.currentChapter?.id === #{id} ? 'bg-zinc-50 dark:bg-zinc-900' : ''"}
            @click={"mediaPlayer.seek(#{chapter.time})"}
            x-effect={"
            if ($store.player.currentChapter?.id === #{id}) {
              $el.scrollIntoView({block: 'center'})
            }
            "}
          >
            <td class="flex items-center space-x-2 border-b border-zinc-100 py-4 pl-4 dark:border-zinc-900">
              <div class="invisible flex-none" x-class={"{invisible: $store.player.currentChapter?.id !== #{id}}"}>
                <FA.icon name="volume-high" class="h-5 w-5 fill-current" />
              </div>
              <p><%= chapter.title %></p>
            </td>

            <td class="border-b border-zinc-100 py-4 pr-4 text-right tabular-nums dark:border-zinc-900">
              <%= format_timecode(chapter.time) %>
            </td>
          </tr>
        <% end %>
      </table>
    <% end %>
    """
  end
end
