defmodule AmbryWeb.BookLive.Show do
  @moduledoc """
  LiveView for showing book details.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.TimeUtils, only: [duration_display: 1]

  alias Ambry.Books
  alias Ambry.Media.Media
  alias Ambry.PubSub

  alias AmbryWeb.Player

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
                  <div class="cursor-pointer fill-current" phx-click={media_click_action(@player, media)}>
                    <%= if playing?(@player, media) do %>
                      <FA.icon name="pause" class="h-7 w-7" />
                    <% else %>
                      <FA.icon name="play" class="h-7 w-7" />
                    <% end %>
                  </div>
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

    if connected?(socket) do
      Player.subscribe_socket!(socket)
    end

    {:ok,
     assign(socket,
       page_title: Books.get_book_description(book),
       book: book,
       player: Player.get_for_socket(socket)
     )}
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :player, action: :updated} = _message, socket) do
    {:noreply, assign(socket, player: Player.get_for_socket(socket))}
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

  defp media_click_action(player, media) do
    if loaded?(player, media) do
      JS.dispatch("ambry:toggle-playback", to: "#media-player")
    else
      JS.dispatch("ambry:load-and-play-media",
        to: "#media-player",
        detail: %{id: media.id}
      )
    end
  end

  defp loaded?(%Player{player_state: %{media_id: media_id}}, %Media{id: media_id}), do: true
  defp loaded?(_player, _media), do: false

  defp playing?(%Player{player_state: %{media_id: media_id}, playback_state: :playing}, %Media{
         id: media_id
       }),
       do: true

  defp playing?(_player, _media), do: false
end
