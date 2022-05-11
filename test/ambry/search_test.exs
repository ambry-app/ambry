defmodule Ambry.SearchTest do
  use Ambry.DataCase

  alias Ambry.Search

  describe "search/1" do
    test "returns authors, books, narrators, and series that match the search term (case insensitive)" do
      media =
        insert(:media,
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, name: "Foo Narrator"))
          ],
          book:
            build(:book,
              title: "Foo Book",
              book_authors: [build(:book_author, author: build(:author, name: "Foo Author"))],
              series_books: [build(:series_book, series: build(:series, name: "Foo Series"))]
            )
        )

      %{
        media_narrators: [%{narrator_id: narrator_id}],
        book: %{
          id: book_id,
          book_authors: [%{author_id: author_id}],
          series_books: [%{series_id: series_id}]
        }
      } = media

      results = Search.search("foo")

      assert [{_, %{id: ^author_id}}] = results[:authors]
      assert [{_, %{id: ^book_id}}] = results[:books]
      assert [{_, %{id: ^narrator_id}}] = results[:narrators]
      assert [{_, %{id: ^series_id}}] = results[:series]
    end
  end
end
