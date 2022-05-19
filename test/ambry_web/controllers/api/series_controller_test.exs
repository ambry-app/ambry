defmodule AmbryWeb.Api.SeriesControllerTest do
  use AmbryWeb.ConnCase

  setup :register_and_put_user_api_token

  describe "GET /api/series/:id" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = get(conn, "/api/series/1")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns the requested series and all of its books", %{conn: conn} do
      %{id: book_id, series_books: [%{series_id: series_id} | _]} = insert(:book)

      conn = get(conn, "/api/series/#{series_id}")

      assert %{
               "data" => %{"id" => ^series_id, "books" => [%{"id" => ^book_id}]}
             } = json_response(conn, 200)
    end
  end
end
