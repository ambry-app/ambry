defmodule AmbryWeb.Api.BookmarkControllerTest do
  use AmbryWeb.ConnCase

  setup :register_and_put_user_api_token

  describe "GET /api/bookmarks/:media_id" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = get(conn, "/api/bookmarks/1")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns a list of the user's bookmarks for a given media", %{conn: conn, user: user} do
      %{id: media_id} = insert(:media)
      insert_list(5, :bookmark, media_id: media_id, user_id: user.id)

      conn = get(conn, "/api/bookmarks/#{media_id}")

      assert %{
               "data" => [%{}, %{}, %{}, %{}, %{}],
               "hasMore" => false
             } = json_response(conn, 200)
    end
  end

  describe "POST /api/bookmarks" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = post(conn, "/api/bookmarks", %{})

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "creates a new bookmark", %{conn: conn} do
      %{id: media_id} = insert(:media)

      label = "Foo"
      position = 123.45

      params = %{
        "bookmark" => %{"label" => label, "position" => position, "media_id" => media_id}
      }

      conn = post(conn, "/api/bookmarks", params)

      assert %{
               "id" => bookmark_id,
               "label" => ^label,
               "position" => ^position
             } = json_response(conn, 200)

      assert Ambry.Media.get_bookmark!(bookmark_id)
    end

    test "raises if params are invalid", %{conn: conn} do
      assert_raise(RuntimeError, fn ->
        post(conn, "/api/bookmarks", %{"bookmark" => %{}})
      end)
    end
  end

  describe "PATCH /api/bookmarks/:bookmark_id" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = patch(conn, "/api/bookmarks/1", %{})

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "updates an existing bookmark", %{conn: conn, user: user} do
      %{id: media_id} = insert(:media)
      %{id: bookmark_id} = insert(:bookmark, label: "Foo", media_id: media_id, user_id: user.id)

      params = %{"bookmark" => %{"label" => "Bar"}}

      conn = patch(conn, "/api/bookmarks/#{bookmark_id}", params)

      assert %{
               "id" => ^bookmark_id,
               "label" => "Bar"
             } = json_response(conn, 200)
    end
  end

  describe "DELETE /api/bookmarks/:bookmark_id" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = delete(conn, "/api/bookmarks/1")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "deletes an existing bookmark", %{conn: conn, user: user} do
      %{id: media_id} = insert(:media)
      %{id: bookmark_id} = insert(:bookmark, media_id: media_id, user_id: user.id)

      conn = delete(conn, "/api/bookmarks/#{bookmark_id}")

      assert response(conn, 201)

      assert_raise(Ecto.NoResultsError, fn ->
        Ambry.Media.get_bookmark!(bookmark_id)
      end)
    end
  end
end
