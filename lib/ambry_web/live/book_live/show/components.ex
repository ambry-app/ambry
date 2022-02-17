defmodule AmbryWeb.BookLive.Show.Components do
  @moduledoc """
  Components for the books show live page.
  """

  use AmbryWeb, :p_component

  def header(assigns) do
    ~H"""
    <div>
      <h1 class="text-4xl"><%= @book.title %></h1>
      <p class="text-xl text-gray-500">
        by <.people_links people={@book.authors} link_class="text-lime-500" />
      </p>

      <div class="text-gray-400">
        <.series_book_links series_books={@book.series_books} />
      </div>
    </div>
    """
  end
end
