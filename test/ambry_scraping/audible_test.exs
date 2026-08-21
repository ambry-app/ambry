defmodule AmbryScraping.AudibleTest do
  use ExUnit.Case, async: false
  use Patch
  use Mneme

  alias AmbryScraping.Audible
  alias AmbryScraping.Audible.Author
  alias AmbryScraping.Audible.Client
  alias AmbryScraping.Audible.Narrator
  alias AmbryScraping.Audible.Product
  alias AmbryScraping.Audible.Series

  describe "search_books/1" do
    test "searches for books given a query" do
      patch(Client, :get, fn _url, _params, _opts ->
        {:ok,
         %{
           status: 200,
           body:
             "test/ambry_scraping/audible/mocks/search_books_jaws.json"
             |> File.read!()
             |> Jason.decode!()
         }}
      end)

      assert {:ok, [book | _rest]} = Audible.search_books("Jaws")

      auto_assert %Product{
                    authors: [%Author{id: "B000APWADA", name: "Peter Benchley"}],
                    cover_image: "https://m.media-amazon.com/images/I/81p4-VU2BXL.jpg",
                    description:
                      "_Jaws_  is the classic, blockbuster thriller that inspired the three-time Academy Award-winning Steven Spielberg movie and made millions of beachgoers afraid to go into the water. Experience the thrill of helpless horror again - or for the first time!\n  \nJaws was number 48 in the American Film Institute's 100 Years...100 Movies, and the film earned the coveted number-one spot on the Bravo network's 100 Scariest Movie Moments countdown.\n  \nThis timeless tale of man-eating terror that spawned a movie franchise, two video games, a Universal Studios theme park attraction, and two musicals is finally available on audio for the first time ever!",
                    format: "unabridged",
                    id: "B002V8ODY8",
                    language: "english",
                    narrators: [%Narrator{name: "Erik Steele"}],
                    published: ~D[2009-04-07],
                    publisher: "Blackstone Audio, Inc.",
                    series: [%Series{id: "B091G3LNPG", sequence: "1", title: "Jaws"}],
                    title: "Jaws"
                  } <- book
    end

    test "returns an empty list if given an empty query" do
      assert {:ok, []} = Audible.search_books("")
    end

    test "filters results by language, configurably" do
      patch(Client, :get, fn _url, _params, _opts ->
        {:ok,
         %{
           status: 200,
           body:
             "test/ambry_scraping/audible/mocks/search_books_jaws.json"
             |> File.read!()
             |> Jason.decode!()
         }}
      end)

      # the fixture holds 14 english products and 1 with no language
      assert {:ok, books} = Audible.search_books("Jaws")
      assert length(books) == 14
      assert Enum.all?(books, &(&1.language == "english"))

      assert {:ok, books} = Audible.search_books("Jaws", language: "any")
      assert length(books) == 15

      assert {:ok, []} = Audible.search_books("Jaws", language: "german")
    end
  end

  # Audible's catalog is regional and an edition existing in one marketplace
  # says nothing about the others, so the operator can ask for several. None
  # of this was covered when it was written.
  describe "marketplaces" do
    defp product(attrs) do
      Map.merge(
        %{
          "asin" => "B000",
          "title" => "A Book",
          "language" => "english",
          "release_date" => "2020-01-01",
          "narrators" => [%{"name" => "A Reader"}]
        },
        attrs
      )
    end

    defp answering(by_marketplace) do
      patch(Client, :get, fn _path, _params, opts ->
        case Map.fetch(by_marketplace, Keyword.fetch!(opts, :marketplace)) do
          {:ok, products} when is_list(products) ->
            {:ok, %{status: 200, body: %{"products" => products}}}

          {:ok, failure} ->
            failure

          :error ->
            {:ok, %{status: 200, body: %{"products" => []}}}
        end
      end)
    end

    test "merges what each regional catalog answered" do
      answering(%{
        "us" => [product(%{"asin" => "US1", "title" => "A Book"})],
        "uk" => [product(%{"asin" => "UK1", "title" => "Another Book"})]
      })

      assert {:ok, books} = Audible.search_books("q", marketplaces: ["us", "uk"])
      assert Enum.map(books, & &1.title) == ["A Book", "Another Book"]
    end

    # The same recording carries a different ASIN in every regional catalog,
    # which is why the key isn't the ASIN.
    test "one recording in two catalogs is one result" do
      answering(%{
        "us" => [product(%{"asin" => "US1"})],
        "uk" => [product(%{"asin" => "UK1"})]
      })

      assert {:ok, [only]} = Audible.search_books("q", marketplaces: ["us", "uk"])
      # the configured order is a preference order
      assert only.id == "US1"
    end

    # The distinction the whole setting exists to make: a catalog that could
    # not be reached is not a catalog with nothing in it. This used to answer
    # plain `{:ok, …}` and the miss was invisible.
    test "a region that could not be reached is reported, with what did answer" do
      answering(%{
        "us" => [product(%{"asin" => "US1"})],
        "uk" => {:ok, %{status: 429, body: %{}}}
      })

      assert {:partial, [only], unreached} = Audible.search_books("q", marketplaces: ["us", "uk"])
      assert only.id == "US1"
      assert unreached =~ "uk"
      assert unreached =~ "429"
    end

    test "every region failing is a failure, not an empty catalog" do
      answering(%{
        "us" => {:error, :timeout},
        "uk" => {:error, :timeout}
      })

      assert {:error, _reason} = Audible.search_books("q", marketplaces: ["us", "uk"])
    end

    test "the operator's spelling of the setting is parsed generously" do
      assert Audible.parse_marketplaces("us, uk") == ["us", "uk"]
      assert Audible.parse_marketplaces("US UK") == ["us", "uk"]
      # a typo costs that one marketplace, not the search
      assert Audible.parse_marketplaces("us, xx") == ["us"]
      # and a setting with nothing usable in it falls back rather than
      # silently disabling Audible
      assert Audible.parse_marketplaces("xx") == ["us"]
      assert Audible.parse_marketplaces(nil) == ["us"]
    end
  end
end
