defmodule AmbryWeb.Api.PlayerStateControllerTest do
  use AmbryWeb.ConnCase

  setup :register_and_put_user_api_token

  describe "GET /api/player_states" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = get(conn, "/api/player_states")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns a list of a user's in-progress player states", %{conn: conn, user: user} do
      %{media: %{id: media_id}} = insert(:player_state, user_id: user.id, status: :in_progress)

      conn = get(conn, "/api/player_states")

      assert %{
               "data" => [%{"id" => ^media_id}],
               "hasMore" => false
             } = json_response(conn, 200)
    end
  end

  describe "GET /api/player_states/:media_id" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = get(conn, "/api/player_states/1")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns the requested player state", %{conn: conn, user: user} do
      %{media: %{id: media_id}} = insert(:player_state, user_id: user.id)

      conn = get(conn, "/api/player_states/#{media_id}")

      assert %{
               "data" => %{"id" => ^media_id}
             } = json_response(conn, 200)
    end
  end

  describe "PATCH /api/player_states/:media_id" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = patch(conn, "/api/player_states/1", %{})

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "updates the position on the given player state", %{conn: conn, user: user} do
      %{media: %{id: media_id}} = insert(:player_state, user_id: user.id)

      conn =
        patch(conn, "/api/player_states/#{media_id}", %{"playerState" => %{"position" => 123.45}})

      assert %{
               "data" => %{"id" => ^media_id, "position" => 123.45}
             } = json_response(conn, 200)
    end

    test "updates the playback rate on the given player state", %{conn: conn, user: user} do
      %{media: %{id: media_id}} = insert(:player_state, user_id: user.id)

      conn =
        patch(conn, "/api/player_states/#{media_id}", %{
          "playerState" => %{"playbackRate" => 1.25}
        })

      assert %{
               "data" => %{"id" => ^media_id, "playbackRate" => 1.25}
             } = json_response(conn, 200)
    end

    test "ignores any other passed attributes", %{conn: conn, user: user} do
      %{media: %{id: media_id}} = insert(:player_state, user_id: user.id)

      conn =
        patch(conn, "/api/player_states/#{media_id}", %{
          "playerState" => %{"foo" => "bar"}
        })

      assert %{
               "data" => %{"id" => ^media_id}
             } = json_response(conn, 200)
    end
  end
end
