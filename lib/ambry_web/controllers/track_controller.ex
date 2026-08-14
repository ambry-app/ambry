defmodule AmbryWeb.TrackController do
  @moduledoc """
  Serves direct-play audio files to authenticated clients.

  A track's stored path is relative to its library root (legacy rows keep a
  `/uploads/...` path), so the lookup goes through the track record and its
  root — never through a path the client supplies, and never through a
  stored absolute.
  """

  use AmbryWeb, :controller

  alias Ambry.Hashids
  alias Ambry.Media
  alias Ambry.Media.MediaTrack
  alias AmbryWeb.FileResponse

  def show(conn, params) do
    with {:ok, [track_id]} <- Hashids.decode(params["id"]),
         {:ok, track} <- Media.fetch_media_track(track_id),
         {:ok, disk_path} <- MediaTrack.disk_path(track),
         %Plug.Conn{state: state} = conn when state != :unset <-
           FileResponse.send(conn, disk_path, track.mime) do
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
