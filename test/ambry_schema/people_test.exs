defmodule AmbrySchema.PeopleTest do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2]
  import Ambry.GraphQLSigil

  setup :register_and_put_user_api_token

  describe "Person node" do
    @query ~G"""
    query Person($id: ID!) {
      node(id: $id) {
        id
        ... on Person {
          name
          description
          imagePath
          authors {
            __typename
          }
          narrators {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves Person fields", %{conn: conn} do
      %{person: person} = insert(:author)
      insert(:narrator, person: person, name: person.name)

      %{
        id: id,
        name: name,
        description: description,
        image_path: image_path
      } = person

      gid = to_global_id("Person", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      assert %{
               "data" => %{
                 "node" => %{
                   "id" => ^gid,
                   "name" => ^name,
                   "description" => ^description,
                   "imagePath" => ^image_path,
                   "authors" => [%{"__typename" => "Author"}],
                   "narrators" => [%{"__typename" => "Narrator"}],
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "Author node" do
    @query ~G"""
    query Author($id: ID!) {
      node(id: $id) {
        id
        ... on Author {
          name
          person {
            __typename
          }
          authoredBooks(first: 1) {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves Author fields", %{conn: conn} do
      %{
        id: id,
        name: name
      } = insert(:author)

      gid = to_global_id("Author", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      assert %{
               "data" => %{
                 "node" => %{
                   "id" => ^gid,
                   "name" => ^name,
                   "person" => %{"__typename" => "Person"},
                   "authoredBooks" => %{"__typename" => "BookConnection"},
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "Narrator node" do
    @query ~G"""
    query Narrator($id: ID!) {
      node(id: $id) {
        id
        ... on Narrator {
          name
          person {
            __typename
          }
          narratedMedia(first: 1) {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves Narrator fields", %{conn: conn} do
      %{
        id: id,
        name: name
      } = insert(:narrator)

      gid = to_global_id("Narrator", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      assert %{
               "data" => %{
                 "node" => %{
                   "id" => ^gid,
                   "name" => ^name,
                   "person" => %{"__typename" => "Person"},
                   "narratedMedia" => %{"__typename" => "MediaConnection"},
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end
end
