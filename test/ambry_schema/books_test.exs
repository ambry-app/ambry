defmodule AmbrySchema.BooksTest do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2]
  import Ambry.GraphQLSigil

  setup :register_and_put_user_api_token

  describe "SeriesBook node" do
    @query ~G"""
    query SeriesBook($id: ID!) {
      node(id: $id) {
        id
        ... on SeriesBook {
          bookNumber
          book {
            __typename
          }
          series {
            __typename
          }
        }
      }
    }
    """
    test "resolves SeriesBook fields", %{conn: conn} do
      %{series_books: [%{id: id, book_number: book_number} | _]} = insert(:book)
      gid = to_global_id("SeriesBook", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      book_number_match = Decimal.to_string(book_number)

      assert %{
               "data" => %{
                 "node" => %{
                   "id" => ^gid,
                   "bookNumber" => ^book_number_match,
                   "book" => %{"__typename" => "Book"},
                   "series" => %{"__typename" => "Series"}
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "Series node" do
    @query ~G"""
    query Series($id: ID!) {
      node(id: $id) {
        id
        ... on Series {
          name
          seriesBooks(first: 1) {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves Series fields", %{conn: conn} do
      %{id: id, name: name} = insert(:series)
      gid = to_global_id("Series", id)

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
                   "seriesBooks" => %{"__typename" => "SeriesBookConnection"},
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "Book node" do
    @query ~G"""
    query Book($id: ID!) {
      node(id: $id) {
        id
        ... on Book {
          title
          published
          authors {
            __typename
          }
          seriesBooks {
            __typename
          }
          media {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves Book fields", %{conn: conn} do
      %{book: book} = insert(:media, status: :ready)

      %{
        id: id,
        title: title,
        published: published
      } = book

      gid = to_global_id("Book", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      published_match = Date.to_string(published)

      assert %{
               "data" => %{
                 "node" => %{
                   "id" => ^gid,
                   "title" => ^title,
                   "published" => ^published_match,
                   "authors" => [%{"__typename" => "Author"} | _],
                   "seriesBooks" => [%{"__typename" => "SeriesBook"} | _],
                   "media" => [%{"__typename" => "Media"} | _],
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "books connection" do
    @query ~G"""
    query Books {
      books(first: 1) {
        __typename
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
               "data" => %{"books" => nil},
               "errors" => [
                 %{
                   "locations" => [%{"column" => 3, "line" => 2}],
                   "message" => "unauthorized",
                   "path" => ["books"]
                 }
               ]
             } = json_response(conn, 200)
    end

    test "resolves the books connection", %{conn: conn} do
      conn =
        post(conn, "/gql", %{
          "query" => @query
        })

      assert %{
               "data" => %{
                 "books" => %{"__typename" => "BookConnection"}
               }
             } = json_response(conn, 200)
    end
  end
end
