defmodule AmbryWeb.SearchLive.Components do
  @moduledoc """
  Components for the search results live page.
  """

  use AmbryWeb, :html

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Media.Editions
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
          <span class={["block aspect-1", if(!@person.thumbnails, do: "rounded-full bg-zinc-800")]}>
            <img
              :if={@person.thumbnails}
              src={@person.thumbnails.large}
              class="h-full w-full rounded-full object-cover object-top"
            />
          </span>
        </.link>
        <p class="font-bold text-zinc-100 group-hover:underline sm:text-lg">
          <.link navigate={~p"/people/#{@person}"}>
            {@person.name}
          </.link>
        </p>
        <p :if={@person.authors != []} class="text-sm text-zinc-200 sm:text-base">
          Author
          <%= case aliases(@person, :authors) do %>
            <% "" -> %>
            <% aliases -> %>
              <span>({aliases})</span>
          <% end %>
        </p>
        <p :if={@person.narrators != []} class="text-sm text-zinc-200 sm:text-base">
          Narrator
          <%= case aliases(@person, :narrators) do %>
            <% "" -> %>
            <% aliases -> %>
              <span>({aliases})</span>
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
          <.book_multi_image thumbnails={thumbnails(@series)} />
        </.link>
        <p class="font-bold text-zinc-100 group-hover:underline sm:text-lg">
          <.link navigate={~p"/series/#{@series}"}>
            {@series.name} (Series)
          </.link>
        </p>
      </div>
      <p class="text-sm text-zinc-200 sm:text-base">
        <.people_links people={@series.series_books |> Enum.flat_map(& &1.book.authors) |> Enum.uniq()} />
      </p>
    </div>
    """
  end

  # Series tile rule (tile system v2): up to 3 covers — the books in
  # series order, each contributing its representative (the newest
  # edition's cover); books with no ready edition are skipped.
  defp thumbnails(series) do
    series.series_books
    |> Enum.sort_by(& &1.book_number, Decimal)
    |> Enum.flat_map(fn series_book ->
      case Editions.from_media(series_book.book.media) do
        [newest | _rest] -> List.wrap(newest.representative.thumbnails)
        [] -> []
      end
    end)
    |> Enum.take(3)
  end
end
