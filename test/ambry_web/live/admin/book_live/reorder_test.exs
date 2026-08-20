defmodule AmbryWeb.Admin.BookLive.ReorderTest do
  @moduledoc """
  Reordering a book's authors and series through the actual form.

  The unit tests cover the changeset; this covers the part that historically
  went wrong — that a move made in the rendered form actually reaches the
  database. A reorder that changes no field is invisible to `cast_assoc`, so
  it is entirely possible for the buttons to look like they work, the list to
  visibly move, and nothing at all to be saved.

  The arrows send no event now: the `reorder-rows` hook swaps two rows'
  hidden inputs and dispatches a change, the way `inputs_for/1` documents
  adding and removing rows. So `move/4` here posts exactly what that hook
  posts, read off the rendered form. **What no test here can cover is the
  hook itself** — there is no JavaScript test setup in this project — so this
  is the server's half of the contract, stated in the browser's own terms.
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

      move(view, "book_authors", 0, :down)
      view |> form("#book-form") |> render_submit()

      assert author_order(book) == [second.id, first.id]
    end

    test "moving one up and saving persists the new order", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      move(view, "book_authors", 1, :up)
      view |> form("#book-form") |> render_submit()

      assert author_order(book) == [second.id, first.id]
    end

    test "the moved row visibly changes place before saving", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, html} = live(conn, ~p"/admin/books/#{book}/edit")
      assert rendered_author_ids(html) == [first.id, second.id]

      html = move(view, "book_authors", 0, :down)
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

    # The arrows at the ends of the list are disabled, and the hook refuses a
    # swap with nothing on the other side, so a move past the end never
    # reaches the server as anything at all. What the server sees is a sort
    # list, and a sort list naming a slot that isn't there is Ecto's business:
    # it builds an empty child for it. That is a form the operator cannot
    # save, not a crash, and it is why the hook checks.
    test "a sort list naming a slot that isn't there does not crash the form", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      html =
        view
        |> form("#book-form")
        |> render_change(%{"book" => %{"book_authors_sort" => ["0", "1", "7"]}})

      # Ecto's own answer, worth writing down: `cast_params/4` pops a missing
      # slot as `%{}`, so a sort list can conjure a blank row. The form shows
      # it and refuses to save it; nothing crashes and nothing is lost.
      assert html |> Floki.parse_document!() |> Floki.find("[name$='[author_id]']") |> length() ==
               3

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

  # Removing a row and reordering the rest are two mechanisms indexing one
  # list, and they disagreed: `_drop` names a *slot*, a move swaps what is
  # *in* two slots, so a move after a delete redirected the delete onto
  # whichever row had just arrived in that slot. Saving then destroyed a row
  # the operator kept and restored the one they removed, silently.
  describe "removing a row, then reordering" do
    test "the delete still lands on the row that was deleted", %{conn: conn} do
      %{book: book, authors: [first, second]} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      drop(view, "book_authors", "1")
      # nothing is left to move, and the row that stayed is the one that stays
      view |> form("#book-form") |> render_submit()

      assert author_order(book) == [first.id]
      refute second.id in author_order(book)
    end

    test "a row removed from the middle takes its neighbours' order with it", %{conn: conn} do
      %{book: book, authors: [first, _second, third]} = book_with_three_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      drop(view, "book_authors", "1")
      move(view, "book_authors", 0, :down)
      view |> form("#book-form") |> render_submit()

      # second is gone because second was removed, and the two that stayed
      # swapped places because that is what was clicked
      assert author_order(book) == [third.id, first.id]
    end

    # One row left is nothing to order, and the row above a deleted last row
    # had a live "move down" pointing at a row that was no longer rendered.
    test "the arrows follow what is on screen, not what is in the changeset", %{conn: conn} do
      %{book: book} = book_with_two_authors()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")
      assert has_element?(view, "[data-role='move-buttons']")

      html = drop(view, "book_authors", "1")
      document = Floki.parse_document!(html)

      assert Floki.find(document, "[name$='[author_id]']") |> length() == 1
      assert Floki.find(document, "[data-role='move-buttons']") == []
    end
  end

  # What the `reorder-rows` hook posts: the two rows' `_sort` values swapped,
  # which is the order, and their `position` values with them, which is what
  # makes the children differ at all. Read off the rendered form, so a test
  # moves a row the way the browser does rather than by inventing params.
  defp move(view, field, from, direction) do
    to = if direction == :up, do: from - 1, else: from + 1
    document = view |> render() |> Floki.parse_document!()

    keys = slot_keys(document, field)
    {from_key, to_key} = {Enum.at(keys, from), Enum.at(keys, to)}
    positions = positions(document, field, keys)

    view
    |> form("#book-form")
    |> render_change(%{
      "book" => %{
        (field <> "_sort") =>
          keys |> List.replace_at(from, to_key) |> List.replace_at(to, from_key),
        field => %{
          from_key => %{"position" => positions[to_key]},
          to_key => %{"position" => positions[from_key]}
        }
      }
    })
  end

  defp slot_keys(document, field) do
    document
    |> Floki.find("input[name='book[#{field}_sort][]']")
    |> Enum.flat_map(&Floki.attribute(&1, "value"))
  end

  defp positions(document, field, keys) do
    Map.new(keys, fn key ->
      [value] =
        document
        |> Floki.find("input[name='book[#{field}][#{key}][position]']")
        |> Floki.attribute("value")

      {key, value}
    end)
  end

  defp drop(view, field, index) do
    view |> form("#book-form") |> render_change(%{"book" => %{(field <> "_drop") => [index]}})
  end

  defp book_with_three_authors do
    book = insert(:book)
    authors = for _ <- 1..3, do: insert(:author)
    {:ok, book} = put_authors(book, Enum.map(authors, & &1.id))

    %{book: book, authors: authors}
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
