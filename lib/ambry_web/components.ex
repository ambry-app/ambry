defmodule AmbryWeb.Components do
  @moduledoc """
  Shared function components used throughout the app.
  """

  use Phoenix.Component
  use Phoenix.HTML
  use PetalComponents

  import Phoenix.LiveView.Helpers

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  alias AmbryWeb.Components.PlayButton
  alias AmbryWeb.Endpoint
  alias AmbryWeb.Router.Helpers, as: Routes

  def logo_with_tagline(assigns) do
    ~H"""
    <h1 class="text-center">
      <img class="mx-auto" style="max-height: 128px;" alt="Ambry" src={Routes.static_path(Endpoint, "/images/logo_256x1056.svg")}>
      <span class="font-semibold text-gray-500">Personal Audiobook Streaming</span>
    </h1>
    """
  end

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
            <p>Book <%= number %></p>
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
            by <.people_links people={book.authors} />
          </p>

          <div class="text-sm text-gray-400">
            <.series_book_links series_books={book.series_books} />
          </div>
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

  # prop player_states, :list
  # prop show_load_more, :boolean, default: false
  # prop load_more, :event
  # prop user, :any, required: true
  # prop browser_id, :string, required: true

  def player_state_tiles(assigns) do
    {load_more, target} = assigns.load_more

    ~H"""
    <div class="grid gap-4 sm:gap-6 md:gap-8 grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
      <%= for player_state <- @player_states do %>
        <div class="text-center text-lg">
          <div class="group">
            <span class="relative block aspect-w-10 aspect-h-15">
              <img
                src={player_state.media.book.image_path}
                class="w-full h-full object-center object-cover rounded-t-lg shadow-md border border-b-0 border-gray-200 filter group-hover:saturate-200"
              />
              <span class="absolute flex">
                <span class="self-center mx-auto h-20 w-20 bg-white bg-opacity-80 group-hover:bg-opacity-100 backdrop-blur-sm rounded-full shadow-md flex group-hover:-translate-y-1 group-hover:shadow-lg transition">
                  <span style="height: 50px;" class="block self-center mx-auto">
                    <.live_component
                      module={PlayButton}
                      id={player_state.media.id}
                      media={player_state.media}
                      user={@user}
                      browser_id={@browser_id}
                    />
                  </span>
                </span>
              </span>
            </span>
            <div class="bg-gray-200 rounded-b-full overflow-hidden shadow-sm">
              <div class="bg-lime-500 h-2" style={"width: #{progress_percent(player_state)}%;"} />
            </div>
          </div>
          <p class="hover:underline">
            <.link
              link_type="live_redirect"
              label={player_state.media.book.title}
              to={Routes.book_show_path(Endpoint, :show, player_state.media.book)}
            />
          </p>
          <p class="text-gray-500">
            by <.people_links people={player_state.media.book.authors} />
          </p>

          <p class="text-gray-500 text-sm">
            Narrated by <.people_links people={player_state.media.narrators} />
            <%= if player_state.media.full_cast do %>
              <span>full cast</span>
            <% end %>
          </p>

          <div class="text-sm text-gray-400">
            <.series_book_links series_books={player_state.media.book.series_books} />
          </div>
        </div>
      <% end %>

      <%= if @show_load_more do %>
        <div class="text-center text-lg">
          <div phx-click={load_more} phx-target={target} class="group">
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

  defp progress_percent(%{position: position, media: %{duration: duration}}) do
    position
    |> Decimal.div(duration)
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  # prop :people, :list, required: true
  # prop :underline, :boolean, default: true
  # prop :link_class, :string

  def people_links(assigns) do
    assigns =
      assign_new(assigns, :classes, fn ->
        underline_class =
          if Map.get(assigns, :underline, true) do
            "hover:underline"
          end

        link_class = assigns[:link_class]

        [underline_class, link_class] |> Enum.join(" ") |> String.trim()
      end)

    ~H"""
    <%= for person_ish <- @people do %>
      <.link
        link_type="live_redirect"
        label={person_ish.name}
        to={Routes.person_show_path(Endpoint, :show, person_ish.person_id)}
        class={@classes}
      /><span class="last:hidden">,</span>
    <% end %>
    """
  end

  # prop :series_books, :list, required: true

  def series_book_links(assigns) do
    ~H"""
    <%= for series_book <- Enum.sort_by(@series_books, & &1.series.name) do %>
      <p>
        <.link
          link_type="live_redirect"
          to={Routes.series_show_path(Endpoint, :show, series_book.series)}
          class="hover:underline"
        >
          <%= series_book.series.name %> #<%= series_book.book_number %>
        </.link>
      </p>
    <% end %>
    """
  end

  def primary_link(assigns) do
    extra_classes = assigns[:class] || ""
    extra = assigns_to_attributes(assigns, [])

    default_classes = "text-lime-500 hover:text-lime-800 hover:underline"

    assigns =
      assigns
      |> assign(:extra, extra)
      |> assign(
        :class,
        String.trim("#{default_classes} #{extra_classes}")
      )

    ~H"""
    <.link class={@class} {@extra} />
    """
  end

  def primary_button(assigns) do
    extra_classes = assigns[:class] || ""
    extra = assigns_to_attributes(assigns, [])

    default_classes =
      "bg-lime-500 text-white font-bold px-5 py-2 rounded focus:outline-none shadow hover:bg-lime-700 transition-colors focus:ring-2 focus:ring-lime-300"

    assigns =
      assigns
      |> assign(:extra, extra)
      |> assign(
        :class,
        String.trim("#{default_classes} #{extra_classes}")
      )

    ~H"""
    <button class={@class} {@extra}>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end
end
