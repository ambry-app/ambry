defmodule AmbryScraping.AudibleTest do
  use ExUnit.Case, async: false
  use Patch
  use Mneme

  alias AmbryScraping.Audible
  alias AmbryScraping.Audible.Author
  alias AmbryScraping.Audible.AuthorDetails
  alias AmbryScraping.Audible.Browser
  alias AmbryScraping.Audible.Client
  alias AmbryScraping.Audible.Narrator
  alias AmbryScraping.Audible.Product
  alias AmbryScraping.Audible.Series

  describe "search_authors/1" do
    test "searches for authors given a query" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/audible/mocks/search_authors_stephen_king.html")}
      end)

      assert {:ok, [author | _rest]} = Audible.search_authors("Stephen King")
      auto_assert %Author{id: "B000AQ0842", name: "Stephen King"} <- author
    end

    test "returns an empty list if given an empty query" do
      assert {:ok, []} = Audible.search_authors("")
    end
  end

  describe "author_details/1" do
    test "fetches the details of an author by their ID" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/audible/mocks/author_details_stephen_king.html")}
      end)

      assert {:ok, author_details} = Audible.author_details("B000AQ0842")

      auto_assert %AuthorDetails{
                    description:
                      "Stephen King is the author of more than fifty books, all of them worldwide bestsellers. His first crime thriller featuring Bill Hodges, MR MERCEDES, won the Edgar Award for best novel and was shortlisted for the CWA Gold Dagger Award.  Both MR MERCEDES and END OF WATCH  received the Goodreads Choice Award for the Best Mystery and Thriller of 2014 and 2016 respectively.\n\nKing co-wrote the bestselling novel Sleeping Beauties with his son Owen King, and many of King's books have been turned into celebrated films and television series including The Shawshank Redemption, Gerald's Game and It.\n\nKing was the recipient of America's prestigious 2014 National Medal of Arts and the 2003 National Book Foundation Medal for distinguished contribution to American Letters. In 2007 he also won the Grand Master Award from the Mystery Writers of America. He lives with his wife Tabitha King in Maine.",
                    id: "B000AQ0842",
                    image:
                      "https://images-na.ssl-images-amazon.com/images/S/amzn-author-media-prod/fkeglaqq0pic05a0v6ieqt4iv5.jpg",
                    name: "Stephen King"
                  } <- author_details
    end

    test "returns an error when the given ID doesn't find an author" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/audible/mocks/author_details_not_found.html")}
      end)

      assert {:error, :not_found} = Audible.author_details("foo")
    end
  end

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
  end
end
