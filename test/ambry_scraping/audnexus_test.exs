defmodule AmbryScraping.AudnexusTest do
  use ExUnit.Case, async: false
  use Patch
  use Mneme

  alias AmbryScraping.Audnexus
  alias AmbryScraping.Audnexus.Author
  alias AmbryScraping.Audnexus.AuthorDetails
  alias AmbryScraping.Audnexus.Chapter
  alias AmbryScraping.Audnexus.Chapters
  alias AmbryScraping.Audnexus.Client

  describe "search_authors" do
    test "searches for authors given a query" do
      patch(Client, :get, fn _path, _opts ->
        {:ok,
         %{
           status: 200,
           body:
             "test/ambry_scraping/audnexus/mocks/search_authors_stephen_king.json"
             |> File.read!()
             |> Jason.decode!()
         }}
      end)

      assert {:ok, [author | _rest]} = Audnexus.search_authors("Stephen King")
      auto_assert %Author{id: "B000AQ0842", name: "Stephen King"} <- author
    end

    test "returns an empty list if given an empty query" do
      assert {:ok, []} = Audnexus.search_authors("")
    end
  end

  describe "author_details" do
    test "fetches the details of an author by their ID" do
      patch(Client, :get, fn _path ->
        {:ok,
         %{
           status: 200,
           body:
             "test/ambry_scraping/audnexus/mocks/author_details_stephen_king.json"
             |> File.read!()
             |> Jason.decode!()
         }}
      end)

      assert {:ok, author_details} = Audnexus.author_details("B000AQ0842")

      auto_assert %AuthorDetails{
                    description:
                      "Stephen King is the author of more than fifty books, all of them worldwide bestsellers. His first crime thriller featuring Bill Hodges, MR MERCEDES, won the Edgar Award for best novel and was shortlisted for the CWA Gold Dagger Award. Both MR MERCEDES and END OF WATCH received the Goodreads Choice Award for the Best Mystery and Thriller of 2014 and 2016 respectively. King co-wrote the bestselling novel Sleeping Beauties with his son Owen King, and many of King's books have been turned into celebrated films and television series including The Shawshank Redemption, Gerald's Game and It. King was the recipient of America's prestigious 2014 National Medal of Arts and the 2003 National Book Foundation Medal for distinguished contribution to American Letters. In 2007 he also won the Grand Master Award from the Mystery Writers of America. He lives with his wife Tabitha King in Maine.",
                    id: "B000AQ0842",
                    image:
                      "https://images-na.ssl-images-amazon.com/images/S/amzn-author-media-prod/fkeglaqq0pic05a0v6ieqt4iv5.jpg",
                    name: "Stephen King"
                  } <- author_details
    end

    test "returns an error when the given ID doesn't find an author" do
      patch(Client, :get, fn _path -> {:ok, %{status: 400}} end)

      assert {:error, :not_found} = Audnexus.author_details("foo")
    end
  end

  describe "book_chapters" do
    test "fetches the chapters of an audiobook by its ID" do
      patch(Client, :get, fn _path, _opts ->
        {:ok,
         %{
           status: 200,
           body:
             "test/ambry_scraping/audnexus/mocks/book_chapters_jaws.json"
             |> File.read!()
             |> Jason.decode!()
         }}
      end)

      assert {:ok, chapters} = Audnexus.book_chapters("B002V8ODY8")

      auto_assert %Chapters{
                    asin: "B002V8ODY8",
                    brand_intro_duration_ms: 2043,
                    brand_outro_duration_ms: 5061,
                    chapters: _chapters
                  } <- chapters

      %Chapters{chapters: [chapter | _rest]} = chapters

      auto_assert %Chapter{
                    length_ms: 879_200,
                    start_offset_ms: 0,
                    start_offset_sec: 0,
                    title: "Chapter 1"
                  } <- chapter
    end

    test "returns an error when the given ID doesn't find a book" do
      patch(Client, :get, fn _path, _opts -> {:ok, %{status: 400}} end)

      assert {:error, :not_found} = Audnexus.book_chapters("foo")
    end
  end
end
