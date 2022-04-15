defmodule AmbryWeb.SearchLive.Results.Components do
  @moduledoc """
  Components for the search results live page.
  """

  use AmbryWeb, :component

  alias AmbryWeb.Endpoint

  def author_results(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl mb-4 sm:text-3xl sm:mb-6 md:text-4xl md:mb-8 lg:text-5xl lg:mb-12 font-bold">
        Authors
      </h1>

      <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
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
      <h1 class="text-2xl mb-4 sm:text-3xl sm:mb-6 md:text-4xl md:mb-8 lg:text-5xl lg:mb-12 font-bold">
        Books
      </h1>

      <Amc.book_tiles books={@books} />
    </div>
    """
  end

  def narrator_results(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl mb-4 sm:text-3xl sm:mb-6 md:text-4xl md:mb-8 lg:text-5xl lg:mb-12 font-bold">
        Narrators
      </h1>

      <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
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
      <h1 class="text-2xl mb-4 sm:text-3xl sm:mb-6 md:text-4xl md:mb-8 lg:text-5xl lg:mb-12 font-bold">
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
        <.link link_type="live_redirect" to={Routes.person_show_path(Endpoint, :show, @person)}>
          <span class="block aspect-w-1 aspect-h-1">
            <img
              src={@person.image_path}
              class="w-full h-full object-top object-cover rounded-full shadow-md border border-gray-200 dark:border-gray-900"
            />
          </span>
        </.link>
        <p class="group-hover:underline sm:text-lg font-bold text-gray-900 dark:text-gray-100">
          <.link link_type="live_redirect" to={Routes.person_show_path(Endpoint, :show, @person)}>
            <%= @name %>
            <%= if @name != @person.name do %>
              <br>
              (<%= @person.name %>)
            <% end %>
          </.link>
        </p>
      </div>
    </div>
    """
  end

  defp series_tiles(assigns) do
    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for series <- @series do %>
        <div class="text-center">
          <div class="group">
            <.link link_type="live_redirect" to={Routes.series_show_path(Endpoint, :show, series)}>
              <span class="block aspect-w-10 aspect-h-15 relative">
                <.series_images series_books={series.series_books} />
              </span>
            </.link>
            <p class="group-hover:underline sm:text-lg font-bold text-gray-900 dark:text-gray-100">
              <.link link_type="live_redirect" to={Routes.series_show_path(Endpoint, :show, series)}>
                <%= series.name %>
              </.link>
            </p>
          </div>
          <p class="text-sm sm:text-base text-gray-800 dark:text-gray-200">
            by <Amc.people_links people={series.series_books |> Enum.flat_map(& &1.book.authors) |> Enum.uniq()} />
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
      class="
        absolute top-0
        w-full h-full
        object-center object-cover
        rounded-lg shadow-md
        border border-gray-200 dark:border-gray-900
      "
    />
    """
  end

  defp series_images(%{series_books: [series_book_1, series_book_2]} = assigns) do
    assigns = assign(assigns, %{series_book_1: series_book_1, series_book_2: series_book_2})

    ~H"""
    <img
      src={@series_book_2.book.image_path}
      class="
        w-full h-full
        object-center object-cover
        rounded-lg shadow-md
        border border-gray-200 dark:border-gray-900
        group-hover:rotate-6 group-hover:translate-y-2 origin-bottom-right
        group-hover:z-30
        transition-transform
      "
    />
    <img
      src={@series_book_1.book.image_path}
      class="
        absolute top-0
        w-full h-full
        object-center object-cover
        rounded-lg shadow-md
        border border-gray-200 dark:border-gray-900
        group-hover:-rotate-6 group-hover:translate-y-2 origin-bottom-left
        group-hover:z-40
        transition-transform
      "
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
      class="
        w-full h-full
        object-center object-cover
        rounded-lg shadow-md
        border border-gray-200 dark:border-gray-900
        group-hover:-rotate-12 group-hover:translate-y-3 origin-bottom-left
        group-hover:z-20
        transition-transform
      "
    />
    <img
      src={@series_book_2.book.image_path}
      class="
        absolute top-0
        w-full h-full
        object-center object-cover
        rounded-lg shadow-md
        border border-gray-200 dark:border-gray-900
        group-hover:rotate-12 group-hover:translate-y-3 origin-bottom-right
        group-hover:z-30
        transition-transform
      "
    />
    <img
      src={@series_book_1.book.image_path}
      class="
        absolute top-0
        w-full h-full
        object-center object-cover
        rounded-lg shadow-md
        border border-gray-200 dark:border-gray-900
        group-hover:z-40
      "
    />
    """
  end
end
