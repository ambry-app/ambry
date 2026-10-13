defmodule AmbryWeb.LibraryLiveTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the library", %{conn: conn} do
    media =
      :media
      |> build(book: build(:book))
      |> with_image()
      |> with_thumbnails()
      |> with_copied_source_files()
      |> insert()
      |> with_output_files()

    %{book: %{title: book_title}} = media

    {:ok, _view, html} = live(conn, ~p"/library")

    assert html =~ html_escape(book_title)
  end

  test "hides unlisted media", %{conn: conn} do
    media =
      insert(:media,
        book: build(:book),
        status: :ready,
        unlisted_at: DateTime.utc_now(:second)
      )

    {:ok, _view, html} = live(conn, ~p"/library")

    refute html =~ html_escape(media.book.title)
  end
end
