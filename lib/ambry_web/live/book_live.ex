defmodule AmbryWeb.BookLive do
  @moduledoc """
  LiveView for showing book details.
  """

  use AmbryWeb, :live_view

  alias Ambry.Books
  alias Ambry.Media.Editions

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-10 p-4 sm:max-w-none sm:space-y-14 sm:p-10 md:max-w-screen-2xl md:p-12 lg:space-y-18 lg:p-16">
      <div>
        <.book_header book={@book} class="xl:text-5xl" />
        <p class="mt-1 text-sm text-zinc-500">
          First published {format_published(@book)}
        </p>
      </div>

      <div>
        <h1 class="mb-4 text-2xl font-bold sm:text-3xl lg:mb-8 lg:text-4xl">Editions</h1>

        <.grid>
          <.edition_tile
            :for={edition <- @editions}
            edition={edition}
            show_title={false}
            show_authors={false}
            show_series={false}
            show_narrators={true}
            show_published={true}
          />
        </.grid>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => book_id}, _session, socket) do
    book = Books.get_book_with_media!(book_id)

    # tile system v2: the page is a flat grid of edition tiles; a book with
    # exactly one edition redirects to that edition's target (a group's
    # target is its first part), and a book with no ready editions is
    # hidden from users entirely
    case Editions.from_media(book.media) do
      [] ->
        {:ok, redirect(socket, to: ~p"/")}

      [only_edition] ->
        {:ok, push_navigate(socket, to: ~p"/audiobooks/#{only_edition.representative}")}

      editions ->
        {:ok,
         assign(socket,
           page_title: Books.get_book_description(book),
           book: book,
           editions: editions
         )}
    end
  end
end
