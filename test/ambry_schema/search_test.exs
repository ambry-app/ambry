defmodule AmbrySchema.SearchTest do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2]
  import Ambry.GraphQLSigil

  setup :register_and_put_user_api_token

  describe "search connections" do
    @query ~G"""
    query Search($query: String!) {
      search(query: $query, first: 50) {
        edges {
          node {
            id
          }
        }
      }
    }
    """

    test "returns an unauthorized error if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: "foo"}
        })

      assert %{
               "data" => %{"search" => nil},
               "errors" => [
                 %{
                   "locations" => [%{"column" => 3, "line" => 2}],
                   "message" => "unauthorized",
                   "path" => ["search"]
                 }
               ]
             } = json_response(conn, 200)
    end

    test "returns book by title", %{conn: conn} do
      %{id: id, title: book_title} = book = insert(:book)
      insert_index!(book)
      gid = to_global_id("Book", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: book_title}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns book by series name", %{conn: conn} do
      %{id: id, series_books: [%{series: %{name: series_name}} | _rest]} = book = insert(:book)
      insert_index!(book)
      gid = to_global_id("Book", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: series_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns book by author name", %{conn: conn} do
      %{id: id, book_authors: [%{author: %{name: author_name}} | _rest]} = book = insert(:book)
      insert_index!(book)
      gid = to_global_id("Book", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: author_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns book by author person name", %{conn: conn} do
      %{id: id, book_authors: [%{author: %{person: %{name: person_name}}} | _rest]} = book = insert(:book)

      insert_index!(book)
      gid = to_global_id("Book", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: person_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns book by media narrator name", %{conn: conn} do
      %{book: %{id: id} = book, media_narrators: [%{narrator: %{name: narrator_name}} | _rest]} = insert(:media)

      insert_index!(book)
      gid = to_global_id("Book", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: narrator_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns book by media narrator person name", %{conn: conn} do
      %{
        book: %{id: id} = book,
        media_narrators: [%{narrator: %{person: %{name: person_name}}} | _rest]
      } = insert(:media)

      insert_index!(book)
      gid = to_global_id("Book", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: person_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns person by name", %{conn: conn} do
      %{id: id, name: person_name} = person = insert(:person)
      insert_index!(person)
      gid = to_global_id("Person", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: person_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns person by author name", %{conn: conn} do
      %{name: author_name, person: %{id: id} = person} = insert(:author)
      insert_index!(person)
      gid = to_global_id("Person", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: author_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns person by narrator name", %{conn: conn} do
      %{name: narrator_name, person: %{id: id} = person} = insert(:narrator)
      insert_index!(person)
      gid = to_global_id("Person", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: narrator_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => [
                     %{
                       "node" => %{"id" => ^gid}
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
    end

    test "returns series by name", %{conn: conn} do
      %{id: book_id, series_books: [%{series: %{id: id, name: series_name} = series} | _rest]} = insert(:book)

      # NOTE: this also indexes the book
      insert_index!(series)
      gid = to_global_id("Series", id)
      book_gid = to_global_id("Book", book_id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: series_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => edges
                 }
               }
             } = json_response(conn, 200)

      # The order is not easily determined with randomly generated book
      # titles and series names

      returned_ids = edges |> Enum.map(& &1["node"]["id"]) |> Enum.sort()
      expected_ids = Enum.sort([gid, book_gid])

      assert returned_ids == expected_ids
    end

    test "returns series by author name", %{conn: conn} do
      %{
        id: book_id,
        series_books: [%{series: %{id: id} = series} | _rest1],
        book_authors: [%{author: %{name: author_name}} | _rest2]
      } = insert(:book)

      # NOTE: this also indexes the book
      insert_index!(series)
      gid = to_global_id("Series", id)
      book_gid = to_global_id("Book", book_id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: author_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => edges
                 }
               }
             } = json_response(conn, 200)

      # The order is not easily determined with randomly generated book
      # titles and series names

      returned_ids = edges |> Enum.map(& &1["node"]["id"]) |> Enum.sort()
      expected_ids = Enum.sort([gid, book_gid])

      assert returned_ids == expected_ids
    end

    test "returns series by author person name", %{conn: conn} do
      %{
        id: book_id,
        series_books: [%{series: %{id: id} = series} | _rest1],
        book_authors: [%{author: %{person: %{name: person_name}}} | _rest2]
      } = insert(:book)

      # NOTE: this also indexes the book
      insert_index!(series)
      gid = to_global_id("Series", id)
      book_gid = to_global_id("Book", book_id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{query: person_name}
        })

      assert %{
               "data" => %{
                 "search" => %{
                   "edges" => edges
                 }
               }
             } = json_response(conn, 200)

      # The order is not easily determined with randomly generated book
      # titles and series names

      returned_ids = edges |> Enum.map(& &1["node"]["id"]) |> Enum.sort()
      expected_ids = Enum.sort([gid, book_gid])

      assert returned_ids == expected_ids
    end
  end
end
