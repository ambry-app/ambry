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
      %{id: id, title: book_title} = :book |> insert() |> with_search_index()
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

    test "returns book (and series) by series name", %{conn: conn} do
      book =
        :book
        |> insert(series_books: [build(:series_book, series: build(:series))])
        |> with_search_index()

      %{id: id, series_books: [%{series: %{id: series_id, name: series_name}}]} = book

      gid = to_global_id("Book", id)
      series_gid = to_global_id("Series", series_id)

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

      assert edges |> Enum.map(& &1["node"]["id"]) |> Enum.sort() == Enum.sort([gid, series_gid])
    end

    test "returns book by author name", %{conn: conn} do
      book =
        :book
        |> insert(
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{id: id, book_authors: [%{author: %{name: author_name}}]} = book

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
      book =
        :book
        |> insert(
          book_authors: [
            build(:book_author, author: build(:author, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{id: id, book_authors: [%{author: %{person: %{name: person_name}}}]} = book

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
      media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{book: %{id: id}, media_narrators: [%{narrator: %{name: narrator_name}}]} = media

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
      media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{
        book: %{id: id},
        media_narrators: [%{narrator: %{person: %{name: person_name}}}]
      } = media

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
      %{id: id, name: person_name} = :person |> insert() |> with_search_index()
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
      person = :person |> insert(authors: [build(:author)]) |> with_search_index()
      %{id: id, authors: [%{name: author_name}]} = person
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
      person = :person |> insert(narrators: [build(:narrator)]) |> with_search_index()
      %{id: id, narrators: [%{name: narrator_name}]} = person
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
      book =
        :book
        |> insert(series_books: [build(:series_book, series: build(:series))])
        |> with_search_index()

      %{id: book_id, series_books: [%{series: %{id: id, name: series_name}}]} = book

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
      book =
        :book
        |> insert(
          series_books: [build(:series_book, series: build(:series))],
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{
        id: book_id,
        series_books: [%{series: %{id: id}}],
        book_authors: [%{author: %{name: author_name}}]
      } = book

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
      book =
        :book
        |> insert(
          series_books: [build(:series_book, series: build(:series))],
          book_authors: [
            build(:book_author, author: build(:author, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{
        id: book_id,
        series_books: [%{series: %{id: id}}],
        book_authors: [%{author: %{person: %{name: person_name}}}]
      } = book

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
