defmodule AmbryWeb.BookLive do
  @moduledoc """
  LiveView for showing book details.
  """

  use AmbryWeb, :live_view

  alias Ambry.Books

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-10 p-4 sm:max-w-none sm:space-y-14 sm:p-10 md:max-w-screen-2xl md:p-12 lg:space-y-18 lg:p-16">
      <div>
        <.book_header book={@book} class="xl:text-5xl" />
        <p class="mt-1 text-sm text-zinc-500">
          First published <%= format_published(@book) %>
        </p>
      </div>

      <%= if @book.media == [] do %>
        <p class="mt-4 font-bold">Sorry, there are currently no audiobooks uploaded for this book.</p>
      <% else %>
        <div>
          <h1 class="mb-4 text-2xl font-bold sm:text-3xl lg:mb-8 lg:text-4xl">Editions</h1>

          <.media_tiles
            media={@book.media}
            show_title={false}
            show_authors={false}
            show_series={false}
            show_narrators={true}
            show_published={true}
          />
        </div>
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => book_id}, _session, socket) do
    book = Books.get_book_with_media!(book_id)

    case book.media do
      [media] ->
        {:ok, push_navigate(socket, to: ~p"/audiobooks/#{media}")}

      _else ->
        {:ok,
         assign(socket,
           page_title: Books.get_book_description(book),
           book: book
         )}
    end
  end
end
