defmodule AmbryWeb.BookLive.Show do
  @moduledoc """
  LiveView for showing book details.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.TimeUtils, only: [duration_display: 1]

  alias Ambry.Books

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md p-4 sm:max-w-none md:max-w-screen-2xl md:p-6 lg:p-8">
      <div class="justify-center sm:flex sm:flex-row">
        <section id="cover" class="mb-4 flex-none sm:mb-0 sm:w-80">
          <div class="mb-8 sm:hidden">
            <.book_header book={@book} />
          </div>
          <img
            src={@book.image_path}
            class="w-full rounded-lg border border-zinc-200 shadow-md dark:border-zinc-900 sm:w-80"
          />
          <p class="mt-2 text-sm text-zinc-500">
            Published <%= Calendar.strftime(@book.published, "%B %-d, %Y") %>
          </p>
          <%= if @book.media != [] do %>
            <h2 class="mt-4 mb-2 text-2xl font-bold text-zinc-900 dark:text-zinc-100">
              Recordings
            </h2>
            <div class="divide-y divide-zinc-300 rounded-sm border border-zinc-200 bg-zinc-50 px-3 text-zinc-800 shadow-md dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-200">
              <%= for media <- @book.media do %>
                <div class="flex items-center space-x-2 py-3">
                  <div class="grow">
                    <p>
                      <span>
                        Narrated by <.people_links people={media.narrators} />
                        <%= if media.full_cast do %>
                          <span>full cast</span>
                        <% end %>
                      </span>
                      <%= if media.abridged do %>
                        <span>(Abridged)</span>
                      <% end %>
                    </p>
                    <p class="text-zinc-600 dark:text-zinc-400">
                      <%= duration_display(media.duration) %>
                    </p>
                  </div>
                  <%!-- <div
                    id={"play-media-#{media.id}"}
                    x-data={"{
                      id: #{media.id},
                      loaded: false
                    }"}
                    x-effect="$store.player.mediaId == id ? loaded = true : loaded = false"
                    @click={"loaded ? mediaPlayer.playPause() : mediaPlayer.loadAndPlayMedia(#{media.id})"}
                    class="cursor-pointer fill-current"
                    phx-hook="goHome"
                  >
                    <span :class="{ hidden: loaded && $store.player.playing }">
                      <FA.icon name="play" class="h-7 w-7" />
                    </span>
                    <span class="hidden" :class="{ hidden: !loaded || !$store.player.playing }">
                      <FA.icon name="pause" class="h-7 w-7" />
                    </span>
                  </div> --%>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="mt-4 font-bold">Sorry, there are no recordings uploaded for this book.</p>
          <% end %>
        </section>
        <section id="description" class="max-w-md sm:ml-10">
          <div class="hidden sm:block">
            <.book_header book={@book} />
          </div>
          <.markdown :if={@book.description} content={@book.description} class="mt-4" />
        </section>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => book_id}, _session, socket) do
    book = Books.get_book_with_media!(book_id)

    {:ok,
     socket
     |> assign(:page_title, Books.get_book_description(book))
     |> assign(:book, book)}
  end

  @impl Phoenix.LiveView
  def handle_event("go-home", _params, socket) do
    {:noreply, push_redirect(socket, to: "/")}
  end

  defp book_header(assigns) do
    ~H"""
    <div>
      <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl">
        <%= @book.title %>
      </h1>
      <p class="pb-4 text-zinc-800 dark:text-zinc-200 sm:text-lg xl:text-xl">
        <span>by <.people_links people={@book.authors} /></span>
      </p>

      <div class="text-sm text-zinc-600 dark:text-zinc-400 sm:text-base">
        <.series_book_links series_books={@book.series_books} />
      </div>
    </div>
    """
  end
end
