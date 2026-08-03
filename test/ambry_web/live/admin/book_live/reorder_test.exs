defmodule AmbryWeb.Admin.BookLive.ReorderTest do
  @moduledoc """
  Reordering a book's authors and series through the actual form.

  The unit tests cover the changeset; this covers the part that historically
  went wrong — that clicking a button in the rendered form actually reaches
  the database. A reorder that changes no field is invisible to `cast_assoc`,
  so it is entirely possible for the buttons to look like they work, the list
  to visibly move, and nothing at all to be saved.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Books
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  describe "authors" do
    test "moving one down and saving persists the new order", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view |> element("[data-role='move-down']:not([disabled])") |> render_click()
      view |> form("#book-form") |> render_submit()

      assert author_order(book) == [second.id, first.id]
    end

    test "moving one up and saving persists the new order", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view |> element("[data-role='move-up']:not([disabled])") |> render_click()
      view |> form("#book-form") |> render_submit()

      assert author_order(book) == [second.id, first.id]
    end

    test "the moved row visibly changes place before saving", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, html} = live(conn, ~p"/admin/books/#{book}/edit")
      assert rendered_author_ids(html) == [first.id, second.id]

      html = view |> element("[data-role='move-down']:not([disabled])") |> render_click()
      assert rendered_author_ids(html) == [second.id, first.id]
    end

    # The ends of the list can't move past themselves, and a stale page that
    # tries anyway must not crash the LiveView.
    test "the buttons are disabled at the ends of the list", %{conn: conn} do
      %{book: book} = book_with_two_authors()

      {:ok, _view, html} = live(conn, ~p"/admin/books/#{book}/edit")

      document = Floki.parse_document!(html)
      assert [_up_disabled] = Floki.find(document, "[data-role='move-up'][disabled]")
      assert [_down_disabled] = Floki.find(document, "[data-role='move-down'][disabled]")
    end

    test "an out-of-range move is ignored rather than crashing", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      render_click(view, "move", %{
        "field" => "book_authors",
        "index" => "9",
        "direction" => "down"
      })

      view |> form("#book-form") |> render_submit()
      assert author_order(book) == [first.id, second.id]
    end

    # Moving up from the top computes index -1, and `Enum.at(list, -1)` is the
    # *last* element — so a careless implementation swaps the first row with
    # the last instead of doing nothing.
    test "moving up from the top does not wrap around to the bottom", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      render_click(view, "move", %{
        "field" => "book_authors",
        "index" => "0",
        "direction" => "up"
      })

      view |> form("#book-form") |> render_submit()
      assert author_order(book) == [first.id, second.id]
    end

    # The field name comes off the wire, so it's resolved against the schema's
    # own associations and nothing else.
    test "a move naming an unknown field is ignored", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      render_click(view, "move", %{
        "field" => "not_an_association",
        "index" => "0",
        "direction" => "down"
      })

      view |> form("#book-form") |> render_submit()
      assert author_order(book) == [first.id, second.id]
    end

    # One author means no ambiguity and nothing to order.
    test "no buttons appear for a single author", %{conn: conn} do
      book = insert(:book)
      author = insert(:author)
      {:ok, book} = put_authors(book, [author.id])

      {:ok, _view, html} = live(conn, ~p"/admin/books/#{book}/edit")

      assert html |> Floki.parse_document!() |> Floki.find("[data-role='move-buttons']") == []
    end
  end

  defp book_with_two_authors do
    book = insert(:book)
    first = insert(:author)
    second = insert(:author)
    {:ok, book} = put_authors(book, [first.id, second.id])

    %{book: book, authors: [first, second]}
  end

  defp put_authors(book, author_ids) do
    params =
      author_ids
      |> Enum.with_index()
      |> Map.new(fn {author_id, index} ->
        {to_string(index), %{"author_id" => author_id, "position" => to_string(index)}}
      end)

    Books.update_book(book, %{
      "book_authors" => params,
      "book_authors_sort" => Enum.map(0..(length(author_ids) - 1), &to_string/1)
    })
  end

  defp author_order(book) do
    book.id
    |> Books.get_book!()
    |> Repo.preload(:book_authors)
    |> Map.fetch!(:book_authors)
    |> Enum.map(& &1.author_id)
  end

  # The autocomplete input carries the author id, so the rendered order of
  # those values is the rendered order of the rows.
  defp rendered_author_ids(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("input[name^='book[book_authors]'][name$='[author_id]']")
    |> Enum.map(&(&1 |> Floki.attribute("value") |> hd() |> String.to_integer()))
  end
end
