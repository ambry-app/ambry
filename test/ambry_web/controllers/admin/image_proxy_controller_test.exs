defmodule AmbryWeb.Admin.ImageProxyControllerTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]

  setup :register_and_log_in_admin_user

  @jpeg_bytes <<0xFF, 0xD8, 0xFF, 0xE0>> <> "fake-jpeg-data"

  test "proxies a remote image with its content type", %{conn: conn} do
    patch(Req, :get, fn opts ->
      assert Keyword.get(opts, :retry) == false

      {:ok,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["image/jpeg"]},
         body: @jpeg_bytes
       }}
    end)

    conn = get(conn, ~p"/admin/image-proxy?url=https://images.example.com/author.jpg")

    assert response(conn, 200) == @jpeg_bytes
    assert response_content_type(conn, :jpeg) =~ "image/jpeg"
    assert get_resp_header(conn, "cache-control") == ["private, max-age=86400"]
  end

  # Hardcover's CDN serves every asset — author photos included — as
  # `application/octet-stream`. Gating on the header 404'd a real PNG.
  test "serves an image the upstream labels application/octet-stream", %{conn: conn} do
    patch(Req, :get, fn _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["application/octet-stream"]},
         body: @jpeg_bytes
       }}
    end)

    conn = get(conn, ~p"/admin/image-proxy?url=https://assets.hardcover.app/author/1/x.png")

    assert response(conn, 200) == @jpeg_bytes
    assert response_content_type(conn, :jpeg) =~ "image/jpeg"
  end

  test "rejects bytes that are not an image", %{conn: conn} do
    patch(Req, :get, fn _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["text/html"]},
         body: "<html></html>"
       }}
    end)

    conn = get(conn, ~p"/admin/image-proxy?url=https://example.com/page")

    assert response(conn, 404)
  end

  # The other direction: trusting the header let a page claiming to be an
  # image be echoed back under an image content type.
  test "rejects a page whose content type claims to be an image", %{conn: conn} do
    patch(Req, :get, fn _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["image/png"]},
         body: "<html></html>"
       }}
    end)

    conn = get(conn, ~p"/admin/image-proxy?url=https://example.com/not-really.png")

    assert response(conn, 404)
  end

  test "rejects non-http schemes without fetching", %{conn: conn} do
    patch(Req, :get, fn _opts -> flunk("must not fetch") end)

    conn = get(conn, ~p"/admin/image-proxy?url=file:///etc/passwd")

    assert response(conn, 404)
  end

  test "upstream errors become 404", %{conn: conn} do
    patch(Req, :get, fn _opts -> {:error, %Mint.TransportError{reason: :nxdomain}} end)

    conn = get(conn, ~p"/admin/image-proxy?url=https://gone.example.com/x.jpg")

    assert response(conn, 404)
  end

  test "requires a url param", %{conn: conn} do
    conn = get(conn, ~p"/admin/image-proxy")

    assert response(conn, 400)
  end
end

defmodule AmbryWeb.Admin.ImageProxyControllerAuthTest do
  use AmbryWeb.ConnCase, async: true

  test "requires an admin user", %{conn: conn} do
    conn = get(conn, ~p"/admin/image-proxy?url=https://example.com/x.jpg")

    assert redirected_to(conn) == ~p"/users/log_in"
  end
end
