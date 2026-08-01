defmodule AmbryWeb.Admin.ImageProxyController do
  @moduledoc """
  Proxies remote metadata-provider images for admin import previews.

  Browsers with tracking protection (e.g. Firefox ETP) block hotlinked
  images from provider CDNs — Amazon's image hosts are on the tracker
  blocklists — so import previews render blank even though the URLs are
  fine and the eventual server-side import succeeds. Serving previews
  same-origin sidesteps that entirely.

  Admin-only, http(s) only, image content types only. Fetching operator-
  supplied remote URLs server-side matches the existing import behavior
  (`UploadHelpers.handle_image_import/1`).
  """

  use AmbryWeb, :controller

  @allowed_content_types ~w(image/jpeg image/png image/webp image/gif)
  @receive_timeout 15_000

  def show(conn, %{"url" => url}) do
    with %URI{scheme: scheme} when scheme in ["http", "https"] <- URI.parse(url),
         {:ok, %{status: 200, body: body} = response} when is_binary(body) <-
           Req.get(url: url, receive_timeout: @receive_timeout, retry: false, decode_body: false),
         [content_type | _rest] <- Req.Response.get_header(response, "content-type"),
         true <- String.starts_with?(content_type, @allowed_content_types) do
      conn
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_resp(200, body)
    else
      _other -> send_resp(conn, 404, "Not Found")
    end
  end

  def show(conn, _params), do: send_resp(conn, 400, "Bad Request")
end
