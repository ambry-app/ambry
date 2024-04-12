defmodule AmbryScraping.GoodReadsTest do
  use ExUnit.Case, async: false
  use Patch
  use Mneme

  alias AmbryScraping.GoodReads
  alias AmbryScraping.GoodReads.AuthorDetails
  alias AmbryScraping.GoodReads.Browser
  alias AmbryScraping.GoodReads.Contributor
  alias AmbryScraping.GoodReads.Edition
  alias AmbryScraping.GoodReads.EditionDetails
  alias AmbryScraping.GoodReads.Editions
  alias AmbryScraping.GoodReads.PublishedDate
  alias AmbryScraping.GoodReads.Series
  alias AmbryScraping.GoodReads.Work

  describe "search_authors/1" do
    test "searches for authors given a query" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/goodreads/mocks/search_authors_stephen_king.html")}
      end)

      assert {:ok, [author | _rest]} = GoodReads.search_authors("Stephen King")

      auto_assert %Contributor{
                    id: "author:3389.Stephen_King",
                    name: "Stephen King",
                    type: "author"
                  } <- author
    end

    test "returns an empty list if given an empty query" do
      assert {:ok, []} = GoodReads.search_authors("")
    end
  end

  describe "author_details/1" do
    test "fetches the details of an author by their ID" do
      patch(Browser, :get_page_html, fn
        "/author/show/3389.Stephen_King", _actions ->
          {:ok,
           File.read!("test/ambry_scraping/goodreads/mocks/author_details_stephen_king.html")}

        "/photo/author/3389.Stephen_King", _actions ->
          {:ok,
           File.read!(
             "test/ambry_scraping/goodreads/mocks/author_details_photos_stephen_king.html"
           )}
      end)

      assert {:ok, author_details} = GoodReads.author_details("author:3389.Stephen_King")

      auto_assert %AuthorDetails{
                    id: "author:3389.Stephen_King",
                    image: "https://images.gr-assets.com/authors/1362814142p8/3389.jpg",
                    name: "Stephen King"
                  } <- author_details
    end

    test "returns an error when the given ID doesn't find an author" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/goodreads/mocks/author_details_not_found.html")}
      end)

      assert {:error, :not_found} = GoodReads.author_details("author:foo")
    end
  end

  describe "search_books/1" do
    test "searches for books given a query" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/goodreads/mocks/search_books_the_shining.html")}
      end)

      assert {:ok, [book | _rest]} = GoodReads.search_books("The Shining")

      auto_assert %Work{
                    contributors: [
                      %Contributor{
                        id: "author:3389.Stephen_King",
                        name: "Stephen King",
                        type: "author"
                      }
                    ],
                    id: "work:849585-the-shining",
                    thumbnail:
                      "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1353277730i/11588._SY75_.jpg",
                    title: "The Shining (The Shining, #1)"
                  } <- book
    end

    test "returns an empty list if given an empty query" do
      assert {:ok, []} = GoodReads.search_books("")
    end
  end

  describe "editions/1" do
    test "returns list of editions for a given book" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/goodreads/mocks/editions_the_shining.html")}
      end)

      assert {:ok, editions} = GoodReads.editions("work:849585-the-shining")

      auto_assert %Editions{
                    editions: _editions,
                    first_published: %PublishedDate{},
                    id: "work:849585-the-shining",
                    primary_author: %Contributor{},
                    title: "The Shining"
                  } <- editions

      %Editions{editions: [edition | _rest]} = editions

      auto_assert %Edition{
                    contributors: [
                      %Contributor{
                        id: "author:3389.Stephen_King",
                        name: "Stephen King",
                        type: "author"
                      }
                    ],
                    format: "1st Paperback edition, Paperback, 497 pages",
                    id: "edition:11588.The_Shining",
                    language: "english",
                    published: %PublishedDate{date: ~D[1980-07-01], display_format: :full},
                    publisher: "New English Library (Hodder & Stoughton)",
                    thumbnail:
                      "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1353277730l/11588._SY75_.jpg",
                    title: "The Shining (The Shining, #1)"
                  } <- edition
    end
  end

  describe "edition_details/1" do
    test "returns the details for a given edition of a book" do
      patch(Browser, :get_page_html, fn _path, _actions ->
        {:ok, File.read!("test/ambry_scraping/goodreads/mocks/edition_details_the_shining.html")}
      end)

      assert {:ok, edition} = GoodReads.edition_details("edition:11588.The_Shining")

      auto_assert %EditionDetails{
                    authors: [
                      %Contributor{
                        id: "author:3389.Stephen_King",
                        name: "Stephen King",
                        type: "author"
                      }
                    ],
                    cover_image:
                      "https://images-na.ssl-images-amazon.com/images/S/compressed.photo.goodreads.com/books/1353277730i/11588.jpg",
                    description:
                      "Jack Torrance's new job at the Overlook Hotel is the perfect chance for a fresh start. As the off-season caretaker at the atmospheric old hotel, he'll have plenty of time to spend reconnecting with his family and working on his writing. But as the harsh winter weather sets in, the idyllic location feels ever more remote...and more sinister. And the only one to notice the strange and terrible forces gathering around the Overlook is Danny Torrance, a uniquely gifted five-year-old.",
                    format: "497 pages, Paperback",
                    id: "edition:11588.The_Shining",
                    language: "English",
                    published: %PublishedDate{date: ~D[1980-07-01], display_format: :full},
                    publisher: "New English Library (Hodder & Stoughton)",
                    series: [
                      %Series{
                        id: "series:117014-the-shining",
                        name: "The Shining",
                        number: "1"
                      }
                    ],
                    title: "The Shining"
                  } <- edition
    end
  end
end
