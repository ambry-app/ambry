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

  @impl Phoenix.LiveView
  def handle_event("go-home", _params, socket) do
    {:noreply, push_redirect(socket, to: "/")}
  end
end
