defmodule AmbryWeb.Api.SessionControllerTest do
  use AmbryWeb.ConnCase

  describe "POST /api/log_in" do
    test "returns a session token for valid credentials", %{conn: conn} do
      user = :user |> build() |> with_password() |> insert()

      conn =
        post(conn, "/api/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_password()}
        })

      assert %{
               "data" => %{"token" => "" <> _}
             } = json_response(conn, 200)
    end

    test "returns unauthorized for invalid password", %{conn: conn} do
      user = :user |> build() |> with_password() |> insert()

      conn =
        post(conn, "/api/log_in", %{
          "user" => %{"email" => user.email, "password" => "invalid"}
        })

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns unauthorized for non-existent user", %{conn: conn} do
      conn =
        post(conn, "/api/log_in", %{
          "user" => %{"email" => "nobody@example.com", "password" => "invalid"}
        })

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end
  end

  describe "DELETE /api/log_out" do
    setup :register_and_put_user_api_token

    test "deletes a user's session", %{conn: conn, token: token} do
      assert Ambry.Accounts.get_user_by_session_token(token)

      conn = delete(conn, "/api/log_out")

      assert "OK" = json_response(conn, 200)

      refute Ambry.Accounts.get_user_by_session_token(token)
    end
  end
end
