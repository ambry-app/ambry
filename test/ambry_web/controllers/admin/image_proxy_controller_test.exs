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

  test "rejects non-image content types", %{conn: conn} do
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
