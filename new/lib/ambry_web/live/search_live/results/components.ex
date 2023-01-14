defmodule AmbryWeb.SearchLive.Results.Components do
  @moduledoc """
  Components for the search results live page.
  """

  use AmbryWeb, :html

  alias AmbryWeb.Endpoint

  def author_results(assigns) do
    ~H"""
    <div>
      <h1 class="mb-4 text-2xl font-bold sm:mb-6 sm:text-3xl md:mb-8 md:text-4xl lg:mb-12 lg:text-5xl">
        Authors
      </h1>

      <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 sm:gap-6 md:grid-cols-4 md:gap-8 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
        <%= for author <- @authors do %>
          <.person_tile name={author.name} person={author.person} />
        <% end %>
      </div>
    </div>
    """
  end

  def book_results(assigns) do
    ~H"""
    <div>
      <h1 class="mb-4 text-2xl font-bold sm:mb-6 sm:text-3xl md:mb-8 md:text-4xl lg:mb-12 lg:text-5xl">
        Books
      </h1>

      <.book_tiles books={@books} />
    </div>
    """
  end

  def narrator_results(assigns) do
    ~H"""
    <div>
      <h1 class="mb-4 text-2xl font-bold sm:mb-6 sm:text-3xl md:mb-8 md:text-4xl lg:mb-12 lg:text-5xl">
        Narrators
      </h1>

      <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 sm:gap-6 md:grid-cols-4 md:gap-8 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
        <%= for narrator <- @narrators do %>
          <.person_tile name={narrator.name} person={narrator.person} />
        <% end %>
      </div>
    </div>
    """
  end

  def series_results(assigns) do
    ~H"""
    <div>
      <h1 class="mb-4 text-2xl font-bold sm:mb-6 sm:text-3xl md:mb-8 md:text-4xl lg:mb-12 lg:text-5xl">
        Series
      </h1>

      <.series_tiles series={@series} />
    </div>
    """
  end

  defp person_tile(assigns) do
    ~H"""
    <div class="text-center">
      <div class="group">
        <.link navigate={~p"/people/#{@person}"}>
          <span class="aspect-w-1 aspect-h-1 block">
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
    <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 sm:gap-6 md:grid-cols-4 md:gap-8 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for series <- @series do %>
        <div class="text-center">
          <div class="group">
            <.link navigate={~p"/series/#{series}"}>
              <span class="aspect-w-10 aspect-h-15 relative block">
                <.series_images series_books={series.series_books} />
              </span>
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
      <% end %>
    </div>
    """
  end

  defp series_images(%{series_books: [series_book]} = assigns) do
    assigns = assign(assigns, :series_book, series_book)

    ~H"""
    <img
      src={@series_book.book.image_path}
      class="absolute top-0 h-full w-full rounded-lg border border-zinc-200 object-cover object-center shadow-md dark:border-zinc-900"
    />
    """
  end

  defp series_images(%{series_books: [series_book_1, series_book_2]} = assigns) do
    assigns = assign(assigns, %{series_book_1: series_book_1, series_book_2: series_book_2})

    ~H"""
    <img
      src={@series_book_2.book.image_path}
      class="h-full w-full origin-bottom-right rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-30 group-hover:translate-y-2 group-hover:rotate-6 dark:border-zinc-900"
    />
    <img
      src={@series_book_1.book.image_path}
      class="absolute top-0 h-full w-full origin-bottom-left rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-40 group-hover:translate-y-2 group-hover:-rotate-6 dark:border-zinc-900"
    />
    """
  end

  defp series_images(%{series_books: [series_book_1, series_book_2, series_book_3 | _]} = assigns) do
    assigns =
      assign(assigns, %{
        series_book_1: series_book_1,
        series_book_2: series_book_2,
        series_book_3: series_book_3
      })

    ~H"""
    <img
      src={@series_book_3.book.image_path}
      class="h-full w-full origin-bottom-left rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-20 group-hover:translate-y-3 group-hover:-rotate-12 dark:border-zinc-900"
    />
    <img
      src={@series_book_2.book.image_path}
      class="absolute top-0 h-full w-full origin-bottom-right rounded-lg border border-zinc-200 object-cover object-center shadow-md transition-transform group-hover:z-30 group-hover:translate-y-3 group-hover:rotate-12 dark:border-zinc-900"
    />
    <img
      src={@series_book_1.book.image_path}
      class="absolute top-0 h-full w-full rounded-lg border border-zinc-200 object-cover object-center shadow-md group-hover:z-40 dark:border-zinc-900"
    />
    """
  end
end
