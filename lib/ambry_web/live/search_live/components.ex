defmodule AmbryWeb.SearchLive.Components do
  @moduledoc """
  Components for the search results live page.
  """

  use AmbryWeb, :html

  def results(%{type: :authors} = assigns), do: ~H"<.author_results authors={@items} />"
  def results(%{type: :books} = assigns), do: ~H"<.book_results books={@items} />"
  def results(%{type: :narrators} = assigns), do: ~H"<.narrator_results narrators={@items} />"
  def results(%{type: :series} = assigns), do: ~H"<.series_results series={@items} />"

  def author_results(assigns) do
    ~H"""
    <section>
      <.section_header>
        Authors
      </.section_header>

      <.grid>
        <.person_tile :for={author <- @authors} name={author.name} person={author.person} />
      </.grid>
    </section>
    """
  end

  def book_results(assigns) do
    ~H"""
    <section>
      <.section_header>
        Books
      </.section_header>

      <.book_tiles books={@books} />
    </section>
    """
  end

  def narrator_results(assigns) do
    ~H"""
    <section>
      <.section_header>
        Narrators
      </.section_header>

      <.grid>
        <.person_tile :for={narrator <- @narrators} name={narrator.name} person={narrator.person} />
      </.grid>
    </section>
    """
  end

  def series_results(assigns) do
    ~H"""
    <section>
      <.section_header>
        Series
      </.section_header>

      <.series_tiles series={@series} />
    </section>
    """
  end

  defp person_tile(assigns) do
    ~H"""
    <div class="text-center">
      <div class="group">
        <.link navigate={~p"/people/#{@person}"}>
          <span class="aspect-1 block">
            <img
              src={@person.image_path}
              class="h-full w-full rounded-full border border-zinc-200 object-cover object-top shadow-md dark:border-zinc-900"
            />
          </span>
        </.link>
        <p class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
          <.link navigate={~p"/people/#{@person}"}>
            <%= @name %>
            <%= if @name != @person.name do %>
              <br /> (<%= @person.name %>)
            <% end %>
          </.link>
        </p>
      </div>
    </div>
    """
  end

  defp series_tiles(assigns) do
    ~H"""
    <.grid>
      <div :for={series <- @series} class="text-center">
        <div class="group">
          <.link navigate={~p"/series/#{series}"}>
            <.series_tile series_books={series.series_books} />
          </.link>
          <p class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
            <.link navigate={~p"/series/#{series}"}>
              <%= series.name %>
            </.link>
          </p>
        </div>
        <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
          by <.people_links people={series.series_books |> Enum.flat_map(& &1.book.authors) |> Enum.uniq()} />
        </p>
      </div>
    </.grid>
    """
  end

  defp series_tile(assigns) do
    ~H"""
    <span class="aspect-1 relative block">
      <.series_images series_books={@series_books} />
    </span>
    """
  end

  defp series_images(%{series_books: [series_book]} = assigns) do
    assigns = assign(assigns, :books, series_book.book)

    ~H"""
    <img
      src={@book.image_path}
      class="absolute top-0 h-full w-full rounded-lg border border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900"
    />
    """
  end

  defp series_images(%{series_books: [series_book_1, series_book_2]} = assigns) do
    assigns = assign(assigns, %{book1: series_book_1.book, book2: series_book_2.book})

    ~H"""
    <img
      src={@book2.image_path}
      class="h-full w-full origin-bottom-right rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-30 group-hover:translate-y-2 group-hover:rotate-6 dark:border-zinc-900"
    />
    <img
      src={@book1.image_path}
      class="absolute top-0 h-full w-full origin-bottom-left rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-40 group-hover:translate-y-2 group-hover:-rotate-6 dark:border-zinc-900"
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
      class="h-full w-full origin-bottom-left rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-20 group-hover:translate-y-3 group-hover:-rotate-12 dark:border-zinc-900"
    />
    <img
      src={@book2.image_path}
      class="absolute top-0 h-full w-full origin-bottom-right rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-30 group-hover:translate-y-3 group-hover:rotate-12 dark:border-zinc-900"
    />
    <img
      src={@book1.image_path}
      class="absolute top-0 h-full w-full rounded-lg border border-zinc-200 object-cover object-center shadow-md group-hover:z-40 dark:border-zinc-900"
    />
    """
  end
end
