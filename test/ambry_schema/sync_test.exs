defmodule AmbrySchema.SyncTest do
  use AmbryWeb.ConnCase

  import Ambry.GraphQLSigil

  alias Ambry.People

  setup :register_and_put_user_api_token

  describe "authorPeopleChangedSince" do
    @query ~G"""
    query Sync($since: DateTime) {
      authorPeopleChangedSince(since: $since) {
        id
        author {
          name
        }
        person {
          name
        }
        insertedAt
        updatedAt
      }
      deletionsSince(since: $since) {
        type
        recordId
      }
    }
    """
    test "returns author-person links and tracks their deletions", %{conn: conn} do
      person = insert(:person, name: "Real Name", authors: [build(:author, name: "Pen Name")])
      %{author_people: [%{id: join_id}]} = person

      conn =
        post(conn, "/gql", %{"query" => @query, "variables" => %{}})

      assert %{
               "data" => %{
                 "authorPeopleChangedSince" => [
                   %{
                     "author" => %{"name" => "Pen Name"},
                     "person" => %{"name" => "Real Name"}
                   }
                 ],
                 "deletionsSince" => []
               }
             } = json_response(conn, 200)

      # unlinking (which here also deletes the orphaned author) records
      # deletions for both the join row and the author
      person = People.get_person!(person.id)

      {:ok, _person} =
        People.update_person(person, %{
          author_people_drop: [0],
          author_people: %{0 => %{id: join_id}}
        })

      conn =
        post(build_conn_with_same_auth(conn), "/gql", %{
          "query" => @query,
          "variables" => %{"since" => "2000-01-01T00:00:00Z"}
        })

      assert %{
               "data" => %{
                 "authorPeopleChangedSince" => [],
                 "deletionsSince" => deletions
               }
             } = json_response(conn, 200)

      assert Enum.any?(deletions, &(&1["type"] == "AUTHOR_PERSON"))
      assert Enum.any?(deletions, &(&1["type"] == "AUTHOR"))
    end
  end

  defp build_conn_with_same_auth(conn) do
    auth_header = Plug.Conn.get_req_header(conn, "authorization")

    Enum.reduce(auth_header, build_conn(), fn value, conn ->
      Plug.Conn.put_req_header(conn, "authorization", value)
    end)
  end
end
