defmodule AmbryWeb.PersonLive do
  @moduledoc """
  LiveView for showing person details.
  """

  use AmbryWeb, :live_view

  alias Ambry.Books
  alias Ambry.People

  # The number of books to show for each author or narrator.
  @books_limit 12

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-16 p-4 sm:max-w-none sm:space-y-24 md:max-w-screen-2xl md:p-6 lg:space-y-32 lg:p-8">
      <div
        :if={@person.image_path || @person.description}
        class="justify-center sm:flex sm:flex-row sm:space-x-10 md:space-x-12 lg:space-x-16"
      >
        <section :if={@person.image_path} id="photo" class="mb-4 min-w-max flex-none sm:mb-0">
          <img
            src={@person.image_path}
            class="mx-auto h-52 w-52 rounded-full object-cover object-top shadow-lg sm:h-64 sm:w-64 md:h-72 md:w-72 lg:h-80 lg:w-80"
          />
        </section>
        <section :if={@person.description} id="description" class="sm:ml-10 md:ml-12 lg:ml-16">
          <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl xl:text-5xl">
            <%= @person.name %>
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

      <div :for={%{author_or_narrator: author, books: books, more?: more?} <- @authored_books}>
        <div class="flex items-baseline gap-4">
          <.books_header>
            Written by <.author_name author={author} person={@person} />
          </.books_header>

          <.link :if={more?} navigate={~p"/authors/#{author}"} class="hover:underline text-zinc-500">
            See all
          </.link>
        </div>

        <.book_tiles books={books} />
      </div>

      <div :for={%{author_or_narrator: narrator, books: books, more?: more?} <- @narrated_books}>
        <div class="flex items-baseline gap-4">
          <.books_header>
            Narrated by <.narrator_name narrator={narrator} person={@person} />
          </.books_header>

          <.link :if={more?} navigate={~p"/narrators/#{narrator}"} class="hover:underline text-zinc-500">
            See all
          </.link>
        </div>

        <.book_tiles books={books} />
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => person_id}, _session, socket) do
    person = People.get_person!(person_id)
    authored_books = get_books(person.authors)
    narrated_books = get_books(person.narrators)

    {:ok,
     assign(socket,
       page_title: person.name,
       person: person,
       authored_books: authored_books,
       narrated_books: narrated_books
     )}
  end

  defp get_books(authors_or_narrators) do
    Enum.flat_map(authors_or_narrators, fn author_or_narrator ->
      case Books.get_authored_books(author_or_narrator, 0, @books_limit) do
        {[], _} -> []
        {books, more?} -> [%{author_or_narrator: author_or_narrator, books: books, more?: more?}]
      end
    end)
  end

  defp books_header(assigns) do
    ~H"""
    <h2 class="mb-6 text-2xl font-bold sm:text-3xl md:mb-8 lg:mb-12 xl:text-4xl">
      <%= render_slot(@inner_block) %>
    </h2>
    """
  end

  attr :author, Ambry.Authors.Author, required: true
  attr :person, People.Person, required: true

  defp author_name(%{author: %{name: name}, person: %{name: name}} = assigns) do
    ~H"""
    <.link navigate={~p"/authors/#{@author}"} class="hover:underline"><%= @author.name %></.link>
    """
  end

  defp author_name(assigns) do
    ~H"""
    <%= @person.name %> as <.link navigate={~p"/authors/#{@author}"} class="hover:underline"><%= @author.name %></.link>
    """
  end

  attr :narrator, Ambry.Narrators.Narrator, required: true
  attr :person, People.Person, required: true

  defp narrator_name(%{narrator: %{name: name}, person: %{name: name}} = assigns) do
    ~H"""
    <.link navigate={~p"/narrators/#{@narrator}"} class="hover:underline"><%= @narrator.name %></.link>
    """
  end

  defp narrator_name(assigns) do
    ~H"""
    <%= @person.name %> as
    <.link navigate={~p"/narrators/#{@narrator}"} class="hover:underline"><%= @narrator.name %></.link>
    """
  end
end
