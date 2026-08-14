defmodule Ambry.CreditPositionsTest do
  @moduledoc """
  Ordering of a book's authors, a book's series and a recording's narrators.

  Before positions existed this order was whatever the rows happened to be
  inserted in — the flat views literally said `ORDER BY author_link.id` —
  which meant an inbox-created book was ordered by whatever a metadata
  provider returned, with no way for the operator to change it.
  """
  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Media
  alias Ambry.Repo

  describe "book authors" do
    test "are numbered in the order they're given" do
      first = insert(:author)
      second = insert(:author)

      {:ok, book} =
        Books.create_book(%{
          title: "Good Omens",
          published: ~D[1990-05-01],
          published_format: :full,
          book_authors: [%{author_id: second.id}, %{author_id: first.id}]
        })

      book = Repo.preload(book, :book_authors)

      assert Enum.map(book.book_authors, &{&1.position, &1.author_id}) == [
               {0, second.id},
               {1, first.id}
             ]
    end

    test "renumber from zero when the list is reordered" do
      book = book_with_authors()
      [a, b, c] = book.book_authors

      book = reorder_authors(book, [c, a, b])

      assert Enum.map(book.book_authors, &{&1.position, &1.id}) == [
               {0, c.id},
               {1, a.id},
               {2, b.id}
             ]
    end

    # Removing an entry must not leave a hole: the survivors are 0 and 1, not
    # 1 and 2, or "the first author" stops meaning position zero.
    test "renumber without a gap when one is dropped" do
      book = book_with_authors()
      [a, _b, c] = book.book_authors

      book = reorder_authors(book, [a, c])

      assert Enum.map(book.book_authors, & &1.position) == [0, 1]
    end

    test "preload comes back in position order, not insertion order" do
      book = book_with_authors()
      [a, b, c] = book.book_authors

      _reordered = reorder_authors(book, [c, b, a])

      reloaded = Book |> Repo.get!(book.id) |> Repo.preload(:book_authors)
      assert Enum.map(reloaded.book_authors, & &1.id) == [c.id, b.id, a.id]
    end

    # `has_many :authors, through: [:book_authors, :author]` inheriting the
    # join's `preload_order` is what lets every existing `preload(:authors)`
    # call site stay untouched. If Ecto ever stops doing that, dozens of
    # display surfaces silently revert to insertion order — so it's pinned
    # here rather than assumed.
    test "the through association inherits the join's ordering" do
      book = book_with_authors()
      [a, b, c] = book.book_authors

      _reordered = reorder_authors(book, [c, a, b])

      reloaded = Book |> Repo.get!(book.id) |> Repo.preload([:authors, :book_authors])

      assert Enum.map(reloaded.authors, & &1.id) ==
               Enum.map(reloaded.book_authors, & &1.author_id)
    end
  end

  describe "media narrators" do
    test "are numbered in the order they're given" do
      book = insert(:book)
      first = insert(:narrator, person: build(:person))
      second = insert(:narrator, person: build(:person))

      {:ok, media} =
        Media.create_media(%{
          book_id: book.id,
          source_path: "/uploads/source_media/#{Ecto.UUID.generate()}",
          media_narrators: [%{narrator_id: second.id}, %{narrator_id: first.id}]
        })

      media = Repo.preload(media, :media_narrators)

      assert Enum.map(media.media_narrators, &{&1.position, &1.narrator_id}) == [
               {0, second.id},
               {1, first.id}
             ]
    end
  end

  describe "book series" do
    # The old flat views ordered a book's series by book_number, which across
    # two different series compares numbers that have nothing to do with each
    # other — #2 of a sub-series sorted ahead of #11 of its parent.
    test "keep the given order even when the lower book number is second" do
      main = insert(:series)
      sub = insert(:series)

      {:ok, book} =
        Books.create_book(%{
          title: "Reaper Man",
          published: ~D[1991-05-01],
          published_format: :full,
          series_books: [
            %{series_id: main.id, book_number: 11},
            %{series_id: sub.id, book_number: 2}
          ]
        })

      book = Repo.preload(book, :series_books)

      assert Enum.map(book.series_books, &{&1.position, &1.series_id}) == [
               {0, main.id},
               {1, sub.id}
             ]
    end
  end

  defp book_with_authors do
    book = insert(:book)
    authors = for _each <- 1..3, do: insert(:author)

    put_authors(book, Enum.map(authors, &%{"author_id" => &1.id}))
  end

  # Keeps each row's identity while changing its place in the list, which is
  # exactly what the form submits after a move.
  defp reorder_authors(book, book_authors) do
    put_authors(book, Enum.map(book_authors, &%{"id" => &1.id, "author_id" => &1.author_id}))
  end

  # The association exactly as a form submits it: an index-keyed map in
  # rendered order, the `_sort` array, and each row's `position`.
  #
  # The position is what makes a reorder register at all. `cast_assoc` orders
  # the params by the sort array, but `cast_relation` discards the result when
  # no child actually changed — and moving a row changes nothing about it.
  # Without a position the reorder is silently a no-op.
  defp put_authors(book, entries) do
    params =
      entries
      |> Enum.with_index()
      |> Map.new(fn {entry, index} ->
        {to_string(index), Map.put(entry, "position", to_string(index))}
      end)

    sort = Enum.map(0..(length(entries) - 1), &to_string/1)

    {:ok, book} =
      Books.update_book(book, %{"book_authors" => params, "book_authors_sort" => sort})

    Repo.preload(book, [:book_authors], force: true)
  end
end
