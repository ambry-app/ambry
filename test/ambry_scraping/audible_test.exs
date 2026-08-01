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
      patch(Client, :get, fn _url, _params ->
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
      patch(Client, :get, fn _url, _params ->
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
end
