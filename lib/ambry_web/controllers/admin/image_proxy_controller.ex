defmodule AmbryWeb.Admin.ImageProxyController do
  @moduledoc """
  Proxies remote metadata-provider images for admin import previews.

  Browsers with tracking protection (e.g. Firefox ETP) block hotlinked
  images from provider CDNs — Amazon's image hosts are on the tracker
  blocklists — so import previews render blank even though the URLs are
  fine and the eventual server-side import succeeds. Serving previews
  same-origin sidesteps that entirely.

  Admin-only, http(s) only, images only. Fetching operator-supplied remote
  URLs server-side matches the existing import behavior
  (`UploadHelpers.handle_image_import/1`).

  What decides "image" is the bytes, not the `content-type` header, because
  the header is not reliably an answer. Hardcover's CDN serves every asset —
  author photos included — as `application/octet-stream`, so gating on the
  header 404'd a perfectly good PNG and left a broken image sitting next to
  the chip offering it. Sniffing is also the stricter reading: a page that
  *claims* `image/png` can no longer be echoed back under an image content
  type, which trusting the header allowed.

  That check is `Ambry.Images.browser_safe/1`, the same one the embedded-art
  path uses — one policy about what a servable image is, so a preview and the
  import it precedes can never disagree about whether something is showable.
  """

  use AmbryWeb, :controller

  @receive_timeout 15_000

  def show(conn, %{"url" => url}) do
    with %URI{scheme: scheme} when scheme in ["http", "https"] <- URI.parse(url),
         {:ok, %{status: 200, body: body}} when is_binary(body) <-
           Req.get(
             url: url,
             headers: [{"user-agent", Ambry.Utils.http_user_agent()}],
             receive_timeout: @receive_timeout,
             retry: false,
             decode_body: false
           ),
         {:ok, image, content_type} <- Ambry.Images.browser_safe(body) do
      conn
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_resp(200, image)
    else
      _other -> send_resp(conn, 404, "Not Found")
    end
  end

  def show(conn, _params), do: send_resp(conn, 400, "Bad Request")
end
