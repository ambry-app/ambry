defmodule AmbryWeb.AudiobookLiveTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders an audiobook show page with its book details", %{conn: conn} do
    media =
      :media
      |> build(book: build(:book))
      |> with_image()
      |> with_thumbnails()
      |> with_copied_source_files()
      |> insert()
      |> with_output_files()

    %{id: media_id, book: %{title: book_title}} = media

    {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media_id}")

    assert html =~ html_escape(book_title)
  end

  test "an unlisted audiobook still renders by direct link", %{conn: conn} do
    media =
      :media
      |> build(book: build(:book), unlisted_at: DateTime.utc_now(:second))
      |> with_image()
      |> with_thumbnails()
      |> with_copied_source_files()
      |> insert()
      |> with_output_files()

    {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media.id}")

    assert html =~ html_escape(media.book.title)
  end

  test "the other-editions rail hides an unlisted edition", %{conn: conn} do
    book = insert(:book)

    media =
      :media
      |> build(book: book)
      |> with_image()
      |> with_thumbnails()
      |> with_copied_source_files()
      |> insert()
      |> with_output_files()

    unlisted =
      insert(:media, book: book, status: :ready, unlisted_at: DateTime.utc_now(:second))

    {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media.id}")

    assert Floki.find(Floki.parse_document!(html), "a[href='/audiobooks/#{unlisted.id}']") == []
  end
end
