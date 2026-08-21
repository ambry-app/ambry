defmodule AmbryWeb.Admin.EmbeddedCoverController do
  @moduledoc """
  Serves a file's embedded cover art, for the forms' preview.

  The embedded candidate's *value* is the audio file to extract from, not a
  URL, so it had nothing to render and the form said "the file's own art" in
  words — which is exactly the wrong answer for the one decision where seeing
  the picture is the whole point. Publishers ship wrong, low-resolution and
  occasionally hilarious embedded art, and choosing between it and a
  provider's cover blind isn't choosing.

  Extracted per request rather than imported: an operator who looks at an item
  and then dismisses it must not leave an orphaned image behind.
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

  # The same question asked of a recording that already exists: an edit form
  # offering the file's own art has to show it for the same reason the import
  # form does.
  #
  # **Through the scanner, which asks the tracks first.** `Media.files/2`
  # reads `source_files`, and those are transcode bookkeeping — what a
  # transcode *consumed* — so an imported recording has none and this found
  # nothing to extract from. The chip rendered a 404 as an image.
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
