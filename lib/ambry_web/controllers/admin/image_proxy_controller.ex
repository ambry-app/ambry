defmodule AmbryWeb.Admin.ImageProxyController do
  @moduledoc """
  Proxies remote metadata-provider images for admin import previews.

  Browsers with tracking protection block hotlinked images from provider CDNs,
  so previews render blank even though the URLs are fine and the eventual
  server-side import succeeds. Serving them same-origin sidesteps that.

  Admin-only, http(s) only, images only.

  **What decides "image" is the bytes, not the `content-type` header**, which
  is not reliably an answer: provider CDNs serve every asset as
  `application/octet-stream`, so gating on the header 404s a perfectly good
  PNG. It is also the stricter reading, since a page that merely *claims*
  `image/png` cannot be echoed back under an image content type.

  That check is `Ambry.Images.browser_safe/1`, the same one the embedded-art
  path uses, so a preview and the import it precedes cannot disagree.

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
