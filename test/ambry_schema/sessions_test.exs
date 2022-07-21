defmodule AmbrySchema.SessionsTest do
  use AmbryWeb.ConnCase

  import Ambry.GraphQLSigil

  describe "createSession mutation" do
    @mutation ~G"""
    mutation CreateSession($input: CreateSessionInput!) {
      createSession(input: $input) {
        token
        user {
          __typename
        }
      }
    }
    """
    test "creates a valid session when given valid credentials", %{conn: conn} do
      user = :user |> build() |> with_password() |> insert()

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => %{input: %{email: user.email, password: valid_password()}}
        })

      assert %{
               "data" => %{
                 "createSession" => %{
                   "token" => encoded_token,
                   "user" => %{"__typename" => "User"}
                 }
               }
             } = json_response(conn, 200)

      token = Base.url_decode64!(encoded_token)
      assert Ambry.Accounts.get_user_by_session_token(token) == user
    end

    test "returns an unauthorized error if given invalid credentials", %{conn: conn} do
      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => %{input: %{email: "bogus", password: "bogus"}}
        })

      assert %{
               "data" => %{"createSession" => nil},
               "errors" => [
                 %{
                   "locations" => [%{"column" => 3, "line" => 2}],
                   "message" => "invalid username or password",
                   "path" => ["createSession"]
                 }
               ]
             } = json_response(conn, 200)
    end
  end

  describe "deleteSession mutation" do
    setup :register_and_put_user_api_token

    @mutation ~G"""
    mutation DeleteSession {
      deleteSession {
        deleted
      }
    }
    """
    test "deletes the existing session if present", %{conn: conn, user: user, token: token} do
      assert Ambry.Accounts.get_user_by_session_token(token) == user

      conn =
        post(conn, "/gql", %{
          "query" => @mutation
        })

      assert %{
               "data" => %{
                 "deleteSession" => %{
                   "deleted" => true
                 }
               }
             } = json_response(conn, 200)

      refute Ambry.Accounts.get_user_by_session_token(token) == user
    end

    test "just doesn't do anything if no session exists", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn =
        post(conn, "/gql", %{
          "query" => @mutation
        })

      assert %{
               "data" => %{
                 "deleteSession" => %{
                   "deleted" => true
                 }
               }
             } = json_response(conn, 200)
    end
  end
end
