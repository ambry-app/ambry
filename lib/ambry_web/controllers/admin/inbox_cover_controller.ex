defmodule AmbryWeb.Admin.InboxCoverController do
  @moduledoc """
  Serves an inbox item's embedded cover art, for the import form's preview.

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

  def show(conn, %{"id" => id}) do
    # The path comes from the item's own files, never from a parameter.
    with {:ok, item} <- Inbox.fetch_item(id),
         [path | _rest] <- item.files,
         {:ok, binary, mime} <- Images.read_embedded(path) do
      conn
      |> put_resp_content_type(mime, nil)
      |> put_resp_header("cache-control", "private, max-age=3600")
      |> send_resp(200, binary)
    else
      _no_image -> send_resp(conn, 404, "Not Found")
    end
  end
end
