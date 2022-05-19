defmodule AmbryWeb.StaticFilesTest do
  use AmbryWeb.ConnCase

  setup :register_and_put_user_api_token

  describe "GET /uploads/:path" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = get(conn, "/uploads/media/non-existent-file")

      assert "Unauthorized" = response(conn, 401)
    end

    test "returns 404 for a non existent file", %{conn: conn} do
      conn = get(conn, "/uploads/media/non-existent-file")

      assert "Not Found" = response(conn, 404)
    end
  end
end
