defmodule AmbryWeb.SearchLive.Results.Components do
  @moduledoc """
  Components for the search results live page.
  """

  use AmbryWeb, :p_component

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
    <div class="text-center text-lg">
      <div class="group">
        <.link link_type="live_redirect" to={Routes.person_show_path(Endpoint, :show, @person)}>
          <span class="block aspect-w-1 aspect-h-1">
            <img
              src={@person.image_path}
              class="w-full h-full object-top object-cover rounded-full shadow-md border border-gray-200 filter group-hover:saturate-200 group-hover:shadow-lg group-hover:-translate-y-1 transition"
            />
          </span>
        </.link>
        <p class="group-hover:underline">
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
        <div class="text-center text-lg">
          <div class="group">
            <.link link_type="live_redirect" to={Routes.series_show_path(Endpoint, :show, series)}>
              <span class="block aspect-w-10 aspect-h-15">
                <img
                  src={hd(series.series_books).book.image_path}
                  class="w-full h-full object-center object-cover rounded-lg shadow-md border border-gray-200 filter group-hover:saturate-200 group-hover:shadow-lg group-hover:-translate-y-1 transition"
                />
              </span>
            </.link>
            <p class="group-hover:underline">
              <.link link_type="live_redirect" to={Routes.series_show_path(Endpoint, :show, series)}>
                <%= series.name %>
              </.link>
            </p>
          </div>
          <p class="text-gray-500">
            by <Amc.people_links people={series.series_books |> Enum.flat_map(& &1.book.authors) |> Enum.uniq()} />
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end
