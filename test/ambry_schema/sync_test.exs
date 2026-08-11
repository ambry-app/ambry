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

  describe "universesChangedSince" do
    @query ~G"""
    query Sync($since: DateTime) {
      universesChangedSince(since: $since) {
        id
        name
      }
      bookUniversesChangedSince(since: $since) {
        id
        book {
          title
        }
        universe {
          name
        }
      }
      deletionsSince(since: $since) {
        type
        recordId
      }
    }
    """
    test "returns universes, memberships, and tracks their deletions", %{conn: conn} do
      book = insert(:book, title: "Warbreaker")

      {:ok, universe} =
        Ambry.Books.create_universe(%{
          name: "Cosmere",
          book_universes: [%{book_id: book.id}]
        })

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{}})

      assert %{
               "data" => %{
                 "universesChangedSince" => [%{"name" => "Cosmere"}],
                 "bookUniversesChangedSince" => [
                   %{
                     "book" => %{"title" => "Warbreaker"},
                     "universe" => %{"name" => "Cosmere"}
                   }
                 ]
               }
             } = json_response(conn, 200)

      {:ok, _universe} = Ambry.Books.delete_universe(Ambry.Books.get_universe!(universe.id))

      conn =
        post(build_conn_with_same_auth(conn), "/gql", %{
          "query" => @query,
          "variables" => %{"since" => "2000-01-01T00:00:00Z"}
        })

      assert %{
               "data" => %{
                 "universesChangedSince" => [],
                 "bookUniversesChangedSince" => [],
                 "deletionsSince" => deletions
               }
             } = json_response(conn, 200)

      assert Enum.any?(deletions, &(&1["type"] == "UNIVERSE"))
      assert Enum.any?(deletions, &(&1["type"] == "BOOK_UNIVERSE"))
    end
  end

  describe "recordingGroupsChangedSince" do
    @query ~G"""
    query Sync($since: DateTime) {
      recordingGroupsChangedSince(since: $since) {
        id
        name
        partsTotal
      }
      mediaChangedSince(since: $since) {
        partNumber
        recordingGroup {
          name
          partsTotal
        }
      }
      deletionsSince(since: $since) {
        type
        recordId
      }
    }
    """
    test "returns groups, part fields, and tracks group deletions", %{conn: conn} do
      book = insert(:book)

      {:ok, group} =
        Ambry.Media.create_recording_group(%{name: "Season One", parts_total: 3})

      {:ok, media} =
        :media
        |> params_for(book_id: book.id, part_number: 1, recording_group_id: group.id)
        |> Map.take([
          :abridged,
          :full_cast,
          :source_path,
          :book_id,
          :part_number,
          :recording_group_id
        ])
        |> Ambry.Media.create_media()

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{}})

      assert %{
               "data" => %{
                 "recordingGroupsChangedSince" => [%{"name" => "Season One", "partsTotal" => 3}],
                 "mediaChangedSince" => [
                   %{
                     "partNumber" => 1,
                     "recordingGroup" => %{"name" => "Season One", "partsTotal" => 3}
                   }
                 ]
               }
             } = json_response(conn, 200)

      # clearing the last member orphan-deletes the group, tracked for sync
      {:ok, _media} =
        Ambry.Media.update_media(Ambry.Media.get_media!(media.id), %{
          "recording_group_id" => ""
        })

      conn =
        post(build_conn_with_same_auth(conn), "/gql", %{
          "query" => @query,
          "variables" => %{"since" => "2000-01-01T00:00:00Z"}
        })

      assert %{
               "data" => %{
                 "recordingGroupsChangedSince" => [],
                 "deletionsSince" => deletions
               }
             } = json_response(conn, 200)

      assert Enum.any?(deletions, &(&1["type"] == "RECORDING_GROUP"))
    end
  end

  defp build_conn_with_same_auth(conn) do
    auth_header = Plug.Conn.get_req_header(conn, "authorization")

    Enum.reduce(auth_header, build_conn(), fn value, conn ->
      Plug.Conn.put_req_header(conn, "authorization", value)
    end)
  end
end
