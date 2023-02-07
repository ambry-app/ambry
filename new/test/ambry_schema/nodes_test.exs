defmodule AmbrySchema.NodeTest do
  use AmbryWeb.ConnCase

  import Ambry.GraphQLSigil

  describe "node" do
    @query ~G"""
    query Node($id: ID!) {
      node(id: $id) {
        id
      }
    }
    """

    test "returns an unauthorized error if missing api token", %{conn: conn} do
      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: "FakeID"}
        })

      assert %{
               "data" => %{"node" => nil},
               "errors" => [
                 %{
                   "locations" => [%{"column" => 3, "line" => 2}],
                   "message" => "unauthorized",
                   "path" => ["node"]
                 }
               ]
             } = json_response(conn, 200)
    end
  end
end
