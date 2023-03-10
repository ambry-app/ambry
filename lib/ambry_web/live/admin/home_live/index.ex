defmodule AmbryWeb.Admin.HomeLive.Index do
  @moduledoc """
  LiveView for admin home screen.
  """

  use AmbryWeb, :admin_live_view

  # import AmbryWeb.Admin.Components

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

  slot :inner_block, required: true

  defp cards_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4 md:grid-cols-3 2xl:grid-cols-6">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :navigate, :string, required: true
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <div class="relative">
      <.link class="absolute top-0 left-0 h-full w-full" navigate={@navigate}></.link>
      <div class="space-y-4 divide-y divide-zinc-200 rounded-sm border border-zinc-200 bg-zinc-50 p-2 dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900 sm:p-4">
        <FA.icon name={@icon} class="mx-auto h-8 w-8 fill-current sm:h-12 sm:w-12" />
        <div class="flex pt-2 sm:pt-4">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  slot :title, required: true
  slot :stat, required: true

  defp stat(assigns) do
    ~H"""
    <div class="grow">
      <h2 class="text-center font-bold sm:text-xl">
        <%= render_slot(@title) %>
      </h2>
      <p class="text-center text-lg font-bold sm:text-2xl">
        <%= render_slot(@stat) %>
      </p>
    </div>
    """
  end
end
