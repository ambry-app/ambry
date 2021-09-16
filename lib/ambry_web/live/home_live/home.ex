defmodule AmbryWeb.HomeLive.Home do
  use AmbryWeb, :live_view

  alias Ambry.Books
  alias Ambry.Media
  alias AmbryWeb.HomeLive.Recent

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  defp recently_played_books(user, offset, limit) do
    player_states = Media.get_recent_player_states(user.id, offset, limit)
    Enum.map(player_states, & &1.media.book)
  end

  defp recently_added_books(offset, limit) do
    Books.get_recent_books!(offset, limit)
  end
end
