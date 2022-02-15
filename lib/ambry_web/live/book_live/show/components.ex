defmodule AmbryWeb.BookLive.Show.Components do
  @moduledoc """
  Components for the books show live page.
  """

  use AmbryWeb, :p_component

  alias AmbryWeb.Endpoint

  def header(assigns) do
    ~H"""
    <div>
      <h1 class="text-4xl"><%= @book.title %></h1>
      <p class="text-xl text-gray-500">
        by
        <%= for author <- @book.authors do %>
          <.link
            link_type="live_redirect"
            label={author.name}
            to={Routes.person_show_path(Endpoint, :show, author.person_id)}
            class="text-lime-500 hover:underline"
          /><span class="last:hidden">,</span>
        <% end %>
      </p>

      <%= for series_book <- Enum.sort_by(@book.series_books, & &1.series.name) do %>
        <p class="text-gray-400">
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
    """
  end
end
