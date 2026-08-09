defmodule AmbryWeb.Admin.HomeLive.Index do
  @moduledoc """
  LiveView for admin home screen.
  """

  use AmbryWeb, :admin_live_view

  # import AmbryWeb.Admin.Components

  alias Ambry.Accounts
  alias Ambry.Books
  alias Ambry.Media
  alias Ambry.People

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Books.subscribe_to_book_crud_messages()
      Books.subscribe_to_series_crud_messages()
      People.subscribe_to_person_crud_messages()
      Media.subscribe_to_media_crud_messages()
    end

    {:ok, count_things(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info(message, socket) when is_struct(message), do: {:noreply, count_things(socket)}

  defp count_things(socket) do
    people_count = People.count_people()
    books_count = Books.count_books()
    series_count = Books.count_series()
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
      {render_slot(@inner_block)}
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
      <div class="rounded-sm border border-zinc-200 bg-zinc-50 p-4 dark:border-zinc-800 dark:bg-zinc-900">
        <.icon name={@icon} class="block h-5 w-5 text-zinc-400 dark:text-zinc-500" />
        <div class="flex gap-8 pt-3">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  slot :title, required: true
  slot :stat, required: true

  defp stat(assigns) do
    ~H"""
    <div>
      <h2 class="text-sm font-semibold text-zinc-500 dark:text-zinc-400">
        {render_slot(@title)}
      </h2>
      <p class="text-2xl font-bold tabular-nums">
        {render_slot(@stat)}
      </p>
    </div>
    """
  end
end
