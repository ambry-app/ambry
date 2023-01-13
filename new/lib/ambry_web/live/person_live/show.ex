defmodule AmbryWeb.PersonLive.Show do
  @moduledoc """
  LiveView for showing person details.
  """

  use AmbryWeb, :live_view

  alias Ambry.People

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-16 p-4 sm:max-w-none sm:space-y-24 md:max-w-screen-2xl md:p-6 lg:space-y-32 lg:p-8">
      <div class="justify-center sm:flex sm:flex-row">
        <section id="photo" class="mb-4 min-w-max flex-none sm:mb-0">
          <img
            src={@person.image_path}
            class="mx-auto h-52 w-52 rounded-full object-cover object-top shadow-lg sm:h-64 sm:w-64 md:h-72 md:w-72 lg:h-80 lg:w-80"
          />
        </section>
        <section id="description" class="sm:ml-10 md:ml-12 lg:ml-16">
          <h1 class="text-3xl font-bold text-zinc-900 dark:text-zinc-100 sm:text-4xl xl:text-5xl">
            <%= @person.name %>
          </h1>
          <%= if @person.description do %>
            <div
              id="readMore"
              phx-hook="readMore"
              data-read-more-label="Read more"
              data-read-less-label="Read less"
              data-read-more-classes="max-h-44 sm:max-h-56"
            >
              <div class="markdown relative mt-4 max-h-44 max-w-md overflow-y-hidden sm:max-h-56">
                <%= raw(Earmark.as_html!(@person.description)) %>
                <div class="absolute bottom-0 hidden h-4 w-full bg-gradient-to-b from-transparent to-white dark:to-black" />
              </div>
              <p class="text-right">
                <span class="text-brand cursor-pointer font-semibold hover:underline dark:text-brand-dark" />
              </p>
            </div>
          <% end %>
        </section>
      </div>

      <%= for author <- @person.authors do %>
        <div>
          <%= if author.name != @person.name do %>
            <h2 class="mb-6 text-2xl font-bold sm:text-3xl md:mb-8 lg:mb-12 xl:text-4xl">
              Written by <%= @person.name %> as <%= author.name %>
            </h2>
          <% else %>
            <h2 class="mb-6 text-2xl font-bold sm:text-3xl md:mb-8 lg:mb-12 xl:text-4xl">
              Written by <%= author.name %>
            </h2>
          <% end %>

          <.book_tiles books={author.books} />
        </div>
      <% end %>

      <%= for narrator <- @person.narrators do %>
        <div>
          <%= if narrator.name != @person.name do %>
            <h2 class="mb-6 text-2xl font-bold sm:text-3xl md:mb-8 lg:mb-12 xl:text-4xl">
              Narrated by <%= @person.name %> as <%= narrator.name %>
            </h2>
          <% else %>
            <h2 class="mb-6 text-2xl font-bold sm:text-3xl md:mb-8 lg:mb-12 xl:text-4xl">
              Narrated by <%= narrator.name %>
            </h2>
          <% end %>

          <.book_tiles books={narrator.books} />
        </div>
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => person_id}, _session, socket) do
    person = People.get_person_with_books!(person_id)

    {:ok,
     socket
     |> assign(:page_title, person.name)
     |> assign(:person, person)}
  end
end
