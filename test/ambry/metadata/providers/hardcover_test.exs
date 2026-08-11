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

    test "a full January 1st date reads as year-only display" do
      patch(Client, :query, fn _config, _query, %{id: 1} ->
        {:ok,
         %{
           "books_by_pk" => %{
             "id" => 1,
             "title" => "Year Only Book",
             "release_date" => "2021-01-01",
             "book_series" => [],
             "contributions" => []
           }
         }}
      end)

      assert {:ok, %Provider.Book{published: published}} = Hardcover.book_details("1", %{})
      assert %Provider.PublishedDate{date: ~D[2021-01-01], display_format: :year} = published
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

  describe "editions/2" do
    defp edition(attrs) do
      Map.merge(
        %{
          "id" => 1,
          "title" => "The Martian",
          "asin" => nil,
          "audio_seconds" => nil,
          "reading_format_id" => 1,
          "release_date" => nil,
          "publisher" => nil,
          "image" => nil,
          "contributions" => []
        },
        attrs
      )
    end

    defp narrated_by(name, role) do
      [%{"contribution" => role, "author" => %{"id" => 250_358, "name" => name}}]
    end

    defp by_author(name) do
      %{"contributions" => [%{"contribution" => nil, "author" => %{"id" => 1, "name" => name}}]}
    end

    # Hardcover files authors under a nil contribution — and on The Martian's
    # B082BHWQCJ the nil-role contributor is Wil Wheaton, its *narrator*. Read
    # off the edition, that record credited Wheaton as an author of the novel.
    # An edition of a book has that book's author by definition.
    test "authors come from the work, not from the edition's own contributions" do
      patch(Client, :query, fn _config, _query, _vars ->
        {:ok,
         %{
           "editions" => [
             edition(%{
               "reading_format_id" => 2,
               "contributions" => narrated_by("Wil Wheaton", nil),
               "book" => by_author("Andy Weir")
             })
           ]
         }}
      end)

      assert {:ok, [book]} = Hardcover.editions("292354", %{})
      assert [%Provider.Contributor{name: "Andy Weir", role: "author"}] = book.authors
    end

    # The Martian has 150 editions on Hardcover, so a `limit` over an
    # unfiltered set decided by nothing at all which ones came back — and
    # R.C. Bray's delisted recording, the exact case `:editions` exists for,
    # was not among them.
    test "asks the server for audio editions rather than filtering a page here" do
      patch(Client, :query, fn _config, query, vars ->
        assert query =~ "reading_format_id: {_eq: 2}"
        assert query =~ "audio_seconds: {_is_null: false}"
        assert query =~ "contribution: {_in: $roles}"
        assert "Narrator" in vars.roles
        {:ok, %{"editions" => []}}
      end)

      assert {:ok, []} = Hardcover.editions("292354", %{})
    end

    # Measured across 400 audiobook editions: "Narrator" 286, "Reading" 9,
    # "Reader" 7, "narrator" 7, "Read by" 5. R.C. Bray is credited on The
    # Martian under four of the five.
    test "recognizes every spelling of the narrator credit" do
      patch(Client, :query, fn _config, _query, _vars ->
        {:ok,
         %{
           "editions" =>
             for {role, id} <- Enum.with_index(["Narrator", "Reader", "Reading", "read by"]) do
               edition(%{"id" => id, "contributions" => narrated_by("R.C. Bray", role)})
             end
         }}
      end)

      assert {:ok, books} = Hardcover.editions("292354", %{})
      assert length(books) == 4
      assert Enum.all?(books, &match?([%Provider.Contributor{name: "R.C. Bray"}], &1.narrators))
    end

    # nil is how Hardcover credits the *author* — Andy Weir is nil on every
    # Martian edition — so reading it as a narrator credits authors as their
    # own readers.
    test "does not read a nil contribution as a narrator credit" do
      patch(Client, :query, fn _config, _query, _vars ->
        {:ok,
         %{
           "editions" => [
             edition(%{
               "reading_format_id" => 2,
               "contributions" => narrated_by("Andy Weir", nil)
             })
           ]
         }}
      end)

      assert {:ok, [book]} = Hardcover.editions("292354", %{})
      assert book.narrators == []
    end

    # Unreliable as a negative (audio editions are stored as format 1), which
    # is why it can't be the filter — but as a positive it is good evidence.
    test "keeps an audiobook-format edition that names no narrator" do
      patch(Client, :query, fn _config, _query, _vars ->
        {:ok, %{"editions" => [edition(%{"reading_format_id" => 2})]}}
      end)

      assert {:ok, [%Provider.Book{narrators: []}]} = Hardcover.editions("292354", %{})
    end

    test "drops a print edition the recall filter swept in" do
      patch(Client, :query, fn _config, _query, _vars ->
        {:ok,
         %{
           "editions" => [
             edition(%{
               "reading_format_id" => 1,
               "contributions" => narrated_by("Some Translator", "Translator")
             })
           ]
         }}
      end)

      assert {:ok, []} = Hardcover.editions("292354", %{})
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
