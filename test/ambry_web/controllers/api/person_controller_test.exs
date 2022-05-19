defmodule AmbryWeb.Api.PersonControllerTest do
  use AmbryWeb.ConnCase

  setup :register_and_put_user_api_token

  describe "GET /api/people/:id" do
    test "returns 401 if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn = get(conn, "/api/people/1")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "returns the requested person", %{conn: conn} do
      %{id: person_id} = insert(:person)

      conn = get(conn, "/api/people/#{person_id}")

      assert %{
               "data" => %{"id" => ^person_id}
             } = json_response(conn, 200)
    end

    test "returns authors and their books", %{conn: conn} do
      %{id: book_id, book_authors: [%{author: %{id: author_id, person: %{id: person_id}}} | _]} =
        insert(:book)

      conn = get(conn, "/api/people/#{person_id}")

      assert %{
               "data" => %{
                 "id" => ^person_id,
                 "authors" => [
                   %{
                     "id" => ^author_id,
                     "books" => [
                       %{"id" => ^book_id}
                     ]
                   }
                 ]
               }
             } = json_response(conn, 200)
    end

    test "returns narrators and their books", %{conn: conn} do
      %{
        book: %{id: book_id},
        media_narrators: [%{narrator: %{id: narrator_id, person: %{id: person_id}}} | _]
      } = insert(:media)

      conn = get(conn, "/api/people/#{person_id}")

      assert %{
               "data" => %{
                 "id" => ^person_id,
                 "narrators" => [
                   %{
                     "id" => ^narrator_id,
                     "books" => [
                       %{"id" => ^book_id}
                     ]
                   }
                 ]
               }
             } = json_response(conn, 200)
    end
  end
end
