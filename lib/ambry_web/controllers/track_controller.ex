defmodule AmbryWeb.TrackController do
  @moduledoc """
  Serves direct-play audio files to authenticated clients.

  The file is served from wherever it actually lives — the uploads tree, a
  local-import folder referenced in place, or (Phase 3) a library root — so
  the lookup goes through the track record rather than through a path the
  client supplies.
  """

  use AmbryWeb, :controller

  alias Ambry.Hashids
  alias Ambry.Media
  alias AmbryWeb.FileResponse

  def show(conn, params) do
    with {:ok, [track_id]} <- Hashids.decode(params["id"]),
         {:ok, track} <- Media.fetch_media_track(track_id),
         %Plug.Conn{state: state} = conn when state != :unset <-
           FileResponse.send(conn, track.path, track.mime) do
      conn
    else
      _else -> not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_layout(false)
    |> put_view(AmbryWeb.ErrorHTML)
    |> render(:"404")
  end
end
