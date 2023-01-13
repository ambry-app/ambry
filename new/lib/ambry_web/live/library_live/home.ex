defmodule AmbryWeb.LibraryLive.Home do
  @moduledoc """
  LiveView for the library page.
  """

  use AmbryWeb, :live_view

  alias AmbryWeb.LibraryLive.Home.{RecentBooks, RecentMedia}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md p-4 sm:max-w-none sm:p-10 md:max-w-screen-2xl md:p-12 lg:p-16">
      <.live_component module={RecentMedia} id="recent-media" user={@current_user} />

      <.live_component module={RecentBooks} id="recent-books" show_admin_links?={@current_user.admin} />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Library")}
  end
end
