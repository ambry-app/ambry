defmodule AmbryWeb.Components do
  @moduledoc """
  Shared function components.
  """

  use AmbryWeb, :p_component

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  alias AmbryWeb.Endpoint

  # prop books, :list, required: true
  # prop show_load_more, :boolean, default: false
  # prop load_more, :event

  def book_tiles(assigns) do
    assigns =
      assigns
      |> assign_new(:show_load_more, fn -> false end)
      |> assign_new(:load_more, fn -> {false, false} end)

    {load_more, target} = assigns.load_more

    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for {book, number} <- books_with_numbers(@books) do %>
        <div class="text-center text-lg">
          <%= if number do %>
            <p>Book {number}</p>
          <% end %>
          <div class="group">
            <.link link_type="live_redirect" to={Routes.book_show_path(Endpoint, :show, book)}>
              <span class="block aspect-w-10 aspect-h-15">
                <img
                  src={book.image_path}
                  class="w-full h-full object-center object-cover rounded-lg shadow-md border border-gray-200 filter group-hover:saturate-200 group-hover:shadow-lg group-hover:-translate-y-1 transition"
                />
              </span>
            </.link>
            <p class="group-hover:underline">
              <.link link_type="live_redirect" to={Routes.book_show_path(Endpoint, :show, book)}>
                <%= book.title %>
              </.link>
            </p>
          </div>
          <p class="text-gray-500">
            by
            <%= for author <- book.authors do %>
              <.link
                link_type="live_redirect"
                label={author.name}
                to={Routes.person_show_path(Endpoint, :show, author.person_id)}
                class="hover:underline"
              /><span class="last:hidden">,</span>
            <% end %>
          </p>

          <%= for series_book <- Enum.sort_by(book.series_books, & &1.series.name) do %>
            <p class="text-sm text-gray-400">
              <.link
                link_type="live_redirect"
                to={Routes.series_show_path(Endpoint, :show, series_book.series)}
                class="hover:underline"
              >
                <%= series_book.series.name %> #<%= series_book.book_number %>
              </.link>
            </p>
          <% end %>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <div class="text-center text-lg">
          <div phx-click={load_more}, phx-target={target} class="group">
            <span class="block aspect-w-10 aspect-h-15 cursor-pointer">
              <span class="load-more bg-gray-200 w-full h-full rounded-lg shadow-md border border-gray-200 group-hover:shadow-lg group-hover:-translate-y-1 transition flex">
                <Heroicons.Outline.dots_horizontal class="self-center mx-auto h-12 w-12" />
              </span>
            </span>
            <p class="group-hover:underline">
              Load more
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp books_with_numbers(books_assign) do
    case books_assign do
      [] -> []
      [%Book{} | _] = books -> Enum.map(books, &{&1, nil})
      [%SeriesBook{} | _] = series_books -> Enum.map(series_books, &{&1.book, &1.book_number})
    end
  end
end
