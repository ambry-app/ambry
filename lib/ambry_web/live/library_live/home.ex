defmodule AmbryWeb.LibraryLive.Home do
  @moduledoc """
  LiveView for the library page.
  """

  use AmbryWeb, :live_view

  alias AmbryWeb.LibraryLive.Home.{RecentBooks, RecentMedia}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Library")}
  end
end
