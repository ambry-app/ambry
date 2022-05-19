defmodule AmbryWeb.Api.BookControllerTest do
  use AmbryWeb.ConnCase

  setup :register_and_put_user_api_token

  describe "GET /api/books" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = get(conn, "/api/books")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns a list of books", %{conn: conn} do
      %{id: book_id} = insert(:book)

      conn = get(conn, "/api/books")

      assert %{
               "data" => [%{"id" => ^book_id}],
               "hasMore" => false
             } = json_response(conn, 200)
    end
  end

  describe "GET /api/books/:id" do
    test "returns 401 if missing api token", %{conn: conn} do
      %{id: book_id} = insert(:book)
      conn = remove_user_api_token(conn)

      conn = get(conn, "/api/books/#{book_id}")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns the requested book", %{conn: conn} do
      %{id: book_id} = insert(:book)

      conn = get(conn, "/api/books/#{book_id}")

      assert %{
               "data" => %{"id" => ^book_id}
             } = json_response(conn, 200)
    end

    test "contains a list of media for the given book", %{conn: conn} do
      %{book: %{id: book_id}} = insert(:media, status: :ready)

      conn = get(conn, "/api/books/#{book_id}")

      assert %{
               "data" => %{"id" => ^book_id, "media" => [%{}]}
             } = json_response(conn, 200)
    end
  end
end
