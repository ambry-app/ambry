defmodule AmbryWeb.HomeLive.Home.Components do
  @moduledoc false

  use AmbryWeb, :p_component

  alias AmbryWeb.Components.PlayButton
  alias AmbryWeb.Endpoint

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
            by
            <%= for author <- player_state.media.book.authors do %>
              <.link
                link_type="live_redirect"
                label={author.name}
                to={Routes.person_show_path(Endpoint, :show, author.person_id)}
                class="hover:underline"
              /><span class="last:hidden">,</span>
            <% end %>
          </p>

          <p class="text-gray-500 text-sm">
            Narrated by
            <%= for narrator <- player_state.media.narrators do %>
              <.link
                link_type="live_redirect"
                label={narrator.name}
                to={Routes.person_show_path(Endpoint, :show, narrator.person_id)}
                class="hover:underline"
              /><span class="last:hidden">,</span>
            <% end %>
            <%= if player_state.media.full_cast do %>
              <span>full cast</span>
            <% end %>
          </p>

          <%= for series_book <- Enum.sort_by(player_state.media.book.series_books, & &1.series.name) do %>
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
end
