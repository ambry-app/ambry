defmodule AmbryWeb.BookLive.Show.Components do
  @moduledoc """
  Components for the books show live page.
  """

  use AmbryWeb, :p_component

  def header(assigns) do
    ~H"""
    <div>
      <h1 class="font-bold text-3xl sm:text-4xl text-gray-900 dark:text-gray-100">
        <%= @book.title %>
      </h1>
      <p class="pb-4 sm:text-lg xl:text-xl text-gray-800 dark:text-gray-200">
        <span>by <Amc.people_links people={@book.authors} /></span>
      </p>

      <div class="text-sm sm:text-base text-gray-600 dark:text-gray-400">
        <Amc.series_book_links series_books={@book.series_books} />
      </div>
    </div>
    """
  end
end