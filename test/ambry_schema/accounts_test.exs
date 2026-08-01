defmodule AmbrySchema.AccountsTest do
  use AmbryWeb.ConnCase

  import Ambry.GraphQLSigil

  setup :register_and_put_user_api_token

  describe "query me" do
    @query ~G"""
    query {
      me {
        email
        admin
        confirmedAt
        insertedAt
        updatedAt
      }
    }
    """
    test "returns an unauthorized error if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn =
        post(conn, "/gql", %{
          "query" => @query
        })

      assert %{
               "data" => %{"me" => nil},
               "errors" => [
                 %{
                   "locations" => [%{"column" => 3, "line" => 2}],
                   "message" => "unauthorized",
                   "path" => ["me"]
                 }
               ]
             } = json_response(conn, 200)
    end

    test "resolves User fields", %{conn: conn, user: user} do
      %{email: email} = user

      conn =
        post(conn, "/gql", %{
          "query" => @query
        })

      assert %{
               "data" => %{
                 "me" => %{
                   "email" => ^email,
                   "admin" => false,
                   "confirmedAt" => nil,
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end
end
