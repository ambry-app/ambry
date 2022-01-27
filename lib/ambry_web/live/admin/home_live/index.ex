defmodule AmbryWeb.Admin.HomeLive.Index do
  @moduledoc """
  LiveView for admin home screen.
  """

  use AmbryWeb, :live_view

  alias Ambry.{Books, Media, People, Series}

  alias Surface.Components.LiveRedirect

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}
  on_mount {AmbryWeb.Admin.Auth, :ensure_mounted_admin_user}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    people_count = People.count_people()
    books_count = Books.count_books()
    series_count = Series.count_series()
    media_count = Media.count_media()

    {:ok,
     assign(socket, %{
       people_count: people_count,
       books_count: books_count,
       series_count: series_count,
       media_count: media_count
     })}
  end
end
