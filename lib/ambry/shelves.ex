defmodule Ambry.Shelves do
  @moduledoc """
  Functions for saving media to shelves.

  This is meant to be flexible for future expansion, but intentionally limited
  in functionality. For now we only want to allow users to "favorite" any media
  they wish, which will create a default shelf under the hood (if it doesn't yet
  exist), and save that media to it.
  """

  def favorite_media(user_id, media_id) do
    with {:ok, shelf} <- get_or_create_favorites_shelf(user_id) do
    end
  end
end
