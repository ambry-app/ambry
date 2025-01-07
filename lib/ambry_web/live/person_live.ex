defmodule AmbryWeb.PersonLive do
  @moduledoc """
  LiveView for showing person details.
  """

  use AmbryWeb, :live_view

  alias Ambry.Books
  alias Ambry.Media
  alias Ambry.People

  # The number of books to show for each author or narrator.
  @books_limit 12

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-16 p-4 sm:max-w-none sm:space-y-24 md:max-w-screen-2xl md:p-6 lg:space-y-32 lg:p-8">
      <div
        :if={@person.thumbnails || @person.description}
        class="justify-center sm:flex sm:flex-row sm:space-x-10 md:space-x-12 lg:space-x-16"
      >
        <section :if={@person.thumbnails} id="photo" class="mb-4 min-w-max flex-none sm:mb-0">
          <img
            src={@person.thumbnails.extra_large}
            class="mx-auto h-52 w-52 rounded-full object-cover object-top shadow-lg sm:h-64 sm:w-64 md:h-72 md:w-72 lg:h-80 lg:w-80"
          />
        </section>
        <section :if={@person.description} id="description" class="sm:ml-10 md:ml-12 lg:ml-16">
          <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl xl:text-5xl">
            {@person.name}
          </h1>
          <div
            id="readMore"
            phx-hook="read-more"
            data-read-more-label="Read more"
            data-read-less-label="Read less"
            data-read-more-classes="max-h-44 sm:max-h-56"
          >
            <div class="markdown relative mt-4 max-h-44 max-w-md overflow-y-hidden sm:max-h-56">
              <.markdown content={@person.description} />
              <div class="absolute bottom-0 hidden h-4 w-full bg-gradient-to-b from-transparent to-white dark:to-black" />
            </div>
            <p class="text-right">
              <span class="text-brand cursor-pointer font-semibold hover:underline dark:text-brand-dark" />
            </p>
          </div>
        </section>
      </div>

      <div :for={%{author: author, books: books, more?: more?} <- @authored_books}>
        <div class="flex items-baseline gap-4">
          <.books_header>
            Written by <.author_name author={author} person={@person} />
          </.books_header>

          <.link :if={more?} navigate={~p"/authors/#{author}"} class="text-zinc-500 hover:underline">
            See all
          </.link>
        </div>

        <.book_tiles books={books} />
      </div>

      <div :for={%{narrator: narrator, media: media, more?: more?} <- @narrated_media}>
        <div class="flex items-baseline gap-4">
          <.books_header>
            Narrated by <.narrator_name narrator={narrator} person={@person} />
          </.books_header>

          <.link :if={more?} navigate={~p"/narrators/#{narrator}"} class="text-zinc-500 hover:underline">
            See all
          </.link>
        </div>

        <.media_tiles media={media} />
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => person_id}, _session, socket) do
    person = People.get_person!(person_id)
    authored_books = get_books(person.authors)
    narrated_media = get_media(person.narrators)

    {:ok,
     assign(socket,
       page_title: person.name,
       person: person,
       authored_books: authored_books,
       narrated_media: narrated_media
     )}
  end

  defp get_books(authors) do
    Enum.flat_map(authors, fn author ->
      case Books.get_authored_books(author, 0, @books_limit) do
        {[], _} -> []
        {books, more?} -> [%{author: author, books: books, more?: more?}]
      end
    end)
  end

  defp get_media(narrators) do
    Enum.flat_map(narrators, fn narrator ->
      case Media.get_narrated_media(narrator, 0, @books_limit) do
        {[], _} -> []
        {media, more?} -> [%{narrator: narrator, media: media, more?: more?}]
      end
    end)
  end

  defp books_header(assigns) do
    ~H"""
    <h2 class="mb-6 text-2xl font-bold sm:text-3xl md:mb-8 lg:mb-12 xl:text-4xl">
      {render_slot(@inner_block)}
    </h2>
    """
  end

  attr :author, Ambry.People.Author, required: true
  attr :person, People.Person, required: true

  defp author_name(%{author: %{name: name}, person: %{name: name}} = assigns) do
    ~H"""
    <.link navigate={~p"/authors/#{@author}"} class="hover:underline">{@author.name}</.link>
    """
  end

  defp author_name(assigns) do
    ~H"""
    {@person.name} as <.link navigate={~p"/authors/#{@author}"} class="hover:underline">{@author.name}</.link>
    """
  end

  attr :narrator, Ambry.People.Narrator, required: true
  attr :person, People.Person, required: true

  defp narrator_name(%{narrator: %{name: name}, person: %{name: name}} = assigns) do
    ~H"""
    <.link navigate={~p"/narrators/#{@narrator}"} class="hover:underline">{@narrator.name}</.link>
    """
  end

  defp narrator_name(assigns) do
    ~H"""
    {@person.name} as <.link navigate={~p"/narrators/#{@narrator}"} class="hover:underline">{@narrator.name}</.link>
    """
  end
end
