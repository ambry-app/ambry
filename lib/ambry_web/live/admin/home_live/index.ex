defmodule AmbryWeb.Admin.HomeLive.Index do
  @moduledoc """
  LiveView for admin home screen.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.{Accounts, Books, Media, People, PubSub, Series}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :ok = PubSub.subscribe("person:*")
      :ok = PubSub.subscribe("book:*")
      :ok = PubSub.subscribe("series:*")
      :ok = PubSub.subscribe("media:*")
    end

    {:ok, count_things(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{}, socket), do: {:noreply, count_things(socket)}

  defp count_things(socket) do
    people_count = People.count_people()
    books_count = Books.count_books()
    series_count = Series.count_series()
    media_count = Media.count_media()
    files_count = Media.Audit.count_files()
    users_count = Accounts.count_users()

    assign(socket, %{
      page_title: "Overview",
      header_title: "Overview",
      people_count: people_count,
      books_count: books_count,
      series_count: series_count,
      media_count: media_count,
      files_count: files_count,
      users_count: users_count
    })
  end

  defp overview_card(assigns) do
    ~H"""
    <div class="relative">
      <.link class="absolute top-0 left-0 w-full h-full" link_type="live_redirect" to={@link} />
      <div class="
        p-2 sm:p-4 rounded-sm border divide-y space-y-4
        bg-gray-50 dark:bg-gray-900 border-gray-200 dark:border-gray-800
        divide-gray-200 dark:divide-gray-800
        ">
        <div>
          <div>
            <FA.icon name={@icon_name} class="w-8 h-8 sm:w-12 sm:h-12 fill-current mx-auto" />
          </div>
        </div>
        <div class="flex pt-2 sm:pt-4">
          <%= for stat <- @stats do %>
            <div class="grow">
              <h2 class="sm:text-xl font-bold text-center">
                <%= stat.title %>
              </h2>
              <p class="text-lg sm:text-2xl font-bold text-center">
                <%= stat.stat %>
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
