defmodule AmbryWeb.SearchLive.Components do
  @moduledoc """
  Components for the search results live page.
  """

  use AmbryWeb, :html

  alias Ambry.Books.Book
  alias Ambry.People.Person
  alias Ambry.Series.Series

  def result_tile(%{result: %Book{}} = assigns) do
    ~H"""
    <.book_tile book={@result} />
    """
  end

  def result_tile(%{result: %Person{}} = assigns) do
    ~H"""
    <.person_tile person={@result} />
    """
  end

  def result_tile(%{result: %Series{}} = assigns) do
    ~H"""
    <.series_tile series={@result} />
    """
  end

  defp person_tile(assigns) do
    ~H"""
    <div class="text-center">
      <div class="group">
        <.link navigate={~p"/people/#{@person}"}>
          <span class="block aspect-1">
            <img
              src={@person.image_path}
              class="h-full w-full rounded-full border border-zinc-200 object-cover object-top shadow-md dark:border-zinc-900"
            />
          </span>
        </.link>
        <p class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
          <.link navigate={~p"/people/#{@person}"}>
            <%= @person.name %>
          </.link>
        </p>
        <p :if={@person.authors != []} class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
          Author
          <%= case aliases(@person, :authors) do %>
            <% "" -> %>
            <% aliases -> %>
              <span>(<%= aliases %>)</span>
          <% end %>
        </p>
        <p :if={@person.narrators != []} class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
          Narrator
          <%= case aliases(@person, :narrators) do %>
            <% "" -> %>
            <% aliases -> %>
              <span>(<%= aliases %>)</span>
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  defp aliases(person, key) do
    person
    |> Map.get(key, [])
    |> Enum.reject(&(&1.name == person.name))
    |> Enum.map_join(", ", & &1.name)
  end

  defp series_tile(assigns) do
    ~H"""
    <div class="text-center">
      <div class="group">
        <.link navigate={~p"/series/#{@series}"}>
          <span class="relative block aspect-1">
            <.series_images series_books={@series.series_books} />
          </span>
        </.link>
        <p class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
          <.link navigate={~p"/series/#{@series}"}>
            <%= @series.name %>
          </.link>
        </p>
      </div>
      <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
        by <.people_links people={@series.series_books |> Enum.flat_map(& &1.book.authors) |> Enum.uniq()} />
      </p>
    </div>
    """
  end

  defp series_images(%{series_books: [series_book]} = assigns) do
    assigns = assign(assigns, :book, series_book.book)

    ~H"""
    <img
      src={@book.image_path}
      class="absolute top-0 h-full w-full rounded-sm border border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900"
    />
    """
  end

  defp series_images(%{series_books: [series_book_1, series_book_2]} = assigns) do
    assigns = assign(assigns, %{book1: series_book_1.book, book2: series_book_2.book})

    ~H"""
    <img
      src={@book2.image_path}
      class="h-full w-full origin-bottom-right rounded-sm border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-30 group-hover:translate-y-2 group-hover:rotate-6 dark:border-zinc-900"
    />
    <img
      src={@book1.image_path}
      class="absolute top-0 h-full w-full origin-bottom-left rounded-sm border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-40 group-hover:translate-y-2 group-hover:-rotate-6 dark:border-zinc-900"
    />
    """
  end

  defp series_images(%{series_books: [series_book_1, series_book_2, series_book_3 | _]} = assigns) do
    assigns =
      assign(assigns, %{
        book1: series_book_1.book,
        book2: series_book_2.book,
        book3: series_book_3.book
      })

    ~H"""
    <img
      src={@book3.image_path}
      class="h-full w-full origin-bottom-left rounded-sm border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-20 group-hover:translate-y-3 group-hover:-rotate-12 dark:border-zinc-900"
    />
    <img
      src={@book2.image_path}
      class="absolute top-0 h-full w-full origin-bottom-right rounded-sm border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-30 group-hover:translate-y-3 group-hover:rotate-12 dark:border-zinc-900"
    />
    <img
      src={@book1.image_path}
      class="absolute top-0 h-full w-full rounded-sm border border-zinc-200 object-cover object-center shadow-md group-hover:z-40 dark:border-zinc-900"
    />
    """
  end
end
