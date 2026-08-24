defmodule AmbryWeb.Admin.EmbeddedCoverController do
  @moduledoc """
  Serves a file's embedded cover art, so the forms can preview it.

  Extracted per request rather than imported: an operator who looks at an
  item and then dismisses it must not leave an orphaned image behind.
  """

  use AmbryWeb, :controller

  alias Ambry.Images
  alias Ambry.Inbox
  alias Ambry.Media

  # The path always comes from the record's own files, never from a parameter.
  def inbox_item(conn, %{"id" => id}) do
    with {:ok, item} <- Inbox.fetch_item(id),
         [path | _rest] <- Inbox.disk_files(item) do
      send_cover(conn, path)
    else
      _no_item -> send_resp(conn, 404, "Not Found")
    end
  end

  # Through the scanner, which asks the tracks first: `Media.files/2` reads
  # `source_files`, which an imported recording does not have.
  def media(conn, %{"id" => id}) do
    with {:ok, media} <- Media.fetch_media(id),
         {:ok, [path | _rest]} <- Media.Scanner.audio_files(media) do
      send_cover(conn, path)
    else
      _no_media -> send_resp(conn, 404, "Not Found")
    end
  end

  defp send_cover(conn, path) do
    case Images.read_embedded(path) do
      {:ok, binary, mime} ->
        conn
        |> put_resp_content_type(mime, nil)
        |> put_resp_header("cache-control", "private, max-age=3600")
        |> send_resp(200, binary)

      _no_image ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
