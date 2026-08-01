defmodule Ambry.Metadata.Providers.HardcoverTest do
  use ExUnit.Case, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.Hardcover
  alias Ambry.Metadata.Providers.Hardcover.Client

  defp fake_token(exp_unix) do
    payload = %{"exp" => exp_unix} |> Jason.encode!() |> Base.url_encode64(padding: false)
    "header.#{payload}.signature"
  end

  defp search_hit do
    %{
      "document" => %{
        "id" => "446681",
        "title" => "Dungeon Crawler Carl",
        "description" => "A man. His ex-girlfriend's cat.",
        "release_date" => "2020-09-21",
        "image" => %{"url" => "https://assets.hardcover.app/edition/31601422/cover.jpeg"},
        "featured_series" => %{
          "position" => 1.0,
          "details" => "1",
          "series" => %{"id" => 12_717, "name" => "Dungeon Crawler Carl"}
        },
        "contributions" => [
          %{"author" => %{"id" => 241_306, "name" => "Matt Dinniman"}},
          %{
            "contribution" => "Cover Artist",
            "author" => %{"id" => 256_731, "name" => "Will Staehle"}
          }
        ]
      }
    }
  end

  describe "search_books/2" do
    test "maps hydrated search hits, keeping only author contributions" do
      patch(Client, :query, fn _config, _query, %{query: "dcc"} ->
        {:ok, %{"search" => %{"results" => %{"hits" => [search_hit()]}}}}
      end)

      assert {:ok, [%Provider.Book{} = book]} = Hardcover.search_books("dcc", %{})
      assert book.provider == "hardcover"
      assert book.title == "Dungeon Crawler Carl"
      assert [%Provider.Contributor{name: "Matt Dinniman", role: "author"}] = book.authors
      assert [%Provider.Series{name: "Dungeon Crawler Carl", number: "1"}] = book.series
      assert %Provider.PublishedDate{date: ~D[2020-09-21], display_format: :full} = book.published
      assert book.cover_url =~ "assets.hardcover.app"
    end

    test "passes through GraphQL errors" do
      patch(Client, :query, fn _config, _query, _vars ->
        {:error, {:graphql, [%{"message" => "field not found"}]}}
      end)

      assert {:error, {:graphql, _errors}} = Hardcover.search_books("q", %{})
    end
  end

  describe "book_details/2" do
    test "fetches and normalizes a book with its full series list" do
      patch(Client, :query, fn _config, _query, %{id: 446_681} ->
        {:ok,
         %{
           "books_by_pk" => %{
             "id" => 446_681,
             "title" => "Dungeon Crawler Carl",
             "release_date" => "2020-09-21",
             "description" => "Desc",
             "image" => %{"url" => "https://assets.hardcover.app/cover.jpeg"},
             "book_series" => [
               %{
                 "position" => 10.5,
                 "details" => nil,
                 "series" => %{"id" => 1, "name" => "Some Series"}
               }
             ],
             "contributions" => [%{"author" => %{"id" => 241_306, "name" => "Matt Dinniman"}}]
           }
         }}
      end)

      assert {:ok, %Provider.Book{} = book} = Hardcover.book_details("446681", %{})
      assert [%Provider.Series{name: "Some Series", number: "10.5"}] = book.series
    end

    test "missing books are not_found" do
      patch(Client, :query, fn _config, _query, _vars -> {:ok, %{"books_by_pk" => nil}} end)

      assert {:error, :not_found} = Hardcover.book_details("999", %{})
    end

    test "non-numeric ids are rejected without a request" do
      patch(Client, :query, fn _config, _query, _vars -> flunk("must not be called") end)

      assert {:error, :invalid_id} = Hardcover.book_details("author:123", %{})
    end
  end

  describe "author search + details" do
    test "search_authors maps hits" do
      patch(Client, :query, fn _config, _query, _vars ->
        {:ok,
         %{
           "search" => %{
             "results" => %{
               "hits" => [
                 %{
                   "document" => %{
                     "id" => "204214",
                     "name" => "Brandon Sanderson",
                     "image" => %{"url" => "https://assets.hardcover.app/author.jpeg"}
                   }
                 }
               ]
             }
           }
         }}
      end)

      assert {:ok, [%Provider.Author{name: "Brandon Sanderson", provider: "hardcover"}]} =
               Hardcover.search_authors("sanderson", %{})
    end

    test "author_details maps bio and image" do
      patch(Client, :query, fn _config, _query, %{id: 241_306} ->
        {:ok,
         %{
           "authors_by_pk" => %{
             "id" => 241_306,
             "name" => "Matt Dinniman",
             "bio" => "Artist and author.",
             "image" => %{"url" => "https://assets.hardcover.app/author.jpg"}
           }
         }}
      end)

      assert {:ok, %Provider.Author{description: "Artist and author."}} =
               Hardcover.author_details("241306", %{})
    end
  end

  describe "availability and token notices" do
    test "unavailable without a token, available with one" do
      refute Hardcover.available?(%{})
      refute Hardcover.available?(%{api_token: ""})
      assert Hardcover.available?(%{api_token: fake_token(0)})
    end

    test "missing token yields a setup warning" do
      assert [{:warning, message}] = Hardcover.config_notices(%{})
      assert message =~ "No API token"
    end

    test "valid far-future token yields an info notice with the expiry date" do
      exp = DateTime.utc_now() |> DateTime.add(300, :day) |> DateTime.to_unix()

      assert [{:info, message}] = Hardcover.config_notices(%{api_token: fake_token(exp)})
      assert message =~ "valid until"
      assert message =~ "expire after one year"
    end

    test "token expiring soon yields a warning" do
      exp = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.to_unix()

      assert [{:warning, message}] = Hardcover.config_notices(%{api_token: fake_token(exp)})
      assert message =~ "expires on"
      assert message =~ "regenerate"
    end

    test "expired token yields an error" do
      exp = DateTime.utc_now() |> DateTime.add(-5, :day) |> DateTime.to_unix()

      assert [{:error, message}] = Hardcover.config_notices(%{api_token: fake_token(exp)})
      assert message =~ "expired on"
    end

    test "undecodable tokens produce no expiry notice" do
      assert [] = Hardcover.config_notices(%{api_token: "not-a-jwt"})
    end
  end

  describe "token_expiry/1" do
    test "decodes the exp claim" do
      assert {:ok, %DateTime{year: 2027}} =
               Hardcover.token_expiry(fake_token(1_817_137_803))
    end

    test "rejects malformed tokens" do
      assert :error = Hardcover.token_expiry("nope")
      assert :error = Hardcover.token_expiry("a.b.c")
    end
  end
end
