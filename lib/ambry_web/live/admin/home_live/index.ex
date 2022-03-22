defmodule AmbryWeb.Admin.HomeLive.Index do
  @moduledoc """
  LiveView for admin home screen.
  """

  use AmbryWeb, :live_view

  alias Ambry.{Books, Media, People, Series}

  alias Surface.Components.LiveRedirect

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    people_count = People.count_people().total
    books_count = Books.count_books()
    series_count = Series.count_series()
    media_count = Media.count_media()

    {:ok,
     assign(socket, %{
       page_title: "Home",
       people_count: people_count,
       books_count: books_count,
       series_count: series_count,
       media_count: media_count
     })}
  end
end
