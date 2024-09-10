defmodule AmbryWeb.SearchLive.Components do
  @moduledoc """
  Components for the search results live page.
  """

  use AmbryWeb, :html

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.People.Person

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
          <span class={["block aspect-1", if(!@person.image_path, do: "rounded-full bg-zinc-200 dark:bg-zinc-800")]}>
            <img
              :if={@person.image_path}
              src={@person.image_path}
              class="h-full w-full rounded-full object-cover object-top"
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
          <.book_multi_image paths={image_paths(@series)} />
        </.link>
        <p class="font-bold text-zinc-900 group-hover:underline dark:text-zinc-100 sm:text-lg">
          <.link navigate={~p"/series/#{@series}"}>
            <%= @series.name %> (Series)
          </.link>
        </p>
      </div>
      <p class="text-sm text-zinc-800 dark:text-zinc-200 sm:text-base">
        by <.people_links people={@series.series_books |> Enum.flat_map(& &1.book.authors) |> Enum.uniq()} />
      </p>
    </div>
    """
  end

  defp image_paths(series) do
    # use the first non-nil image path from each book in the series
    series.series_books
    |> Enum.map(fn series_book ->
      Enum.find_value(series_book.book.media, fn media ->
        media.image_path
      end)
    end)
    |> Enum.filter(& &1)
  end
end
