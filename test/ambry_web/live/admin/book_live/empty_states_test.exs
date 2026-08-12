defmodule AmbryWeb.Admin.BookLive.EmptyStatesTest do
  @moduledoc """
  An empty list states itself instead of rendering a bare grey slab — and a
  list with no rows wears no provenance flag, whatever a past save stamped
  ("Series from you" on a book with no series was the tell).
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  defp lone_book do
    insert(:book,
      title: "Standalone",
      series_books: [],
      book_universes: [],
      book_authors: [
        build(:book_author, author: build(:author, name: "Sole Author", person: build(:person)))
      ]
    )
  end

  test "empty series and universe lists say so", %{conn: conn} do
    book = lone_book()

    {:ok, _view, html} = live(conn, ~p"/admin/books/#{book.id}/edit")

    assert html =~ "Not in a series."
    assert html =~ "Not in a universe."
  end

  # The importer used to stamp `series_books = manual` on every zero-series
  # import (an empty list still counts as a change on a new record), and the
  # flag rendered off the entry alone — so the form claimed "Series from you"
  # about a list with nothing in it.
  test "an empty list wears no provenance flag, even with a stale entry", %{conn: conn} do
    book = lone_book()

    book
    |> Ecto.Changeset.change(
      field_provenance: %{"series_books" => %{"source" => "manual", "locked" => true}}
    )
    |> Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/admin/books/#{book.id}/edit")

    refute html =~ "from you"
  end
end
