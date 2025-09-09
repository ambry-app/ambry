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
      |> with_source_files()
      |> insert()
      |> with_output_files()

    %{id: media_id, book: %{title: book_title}} = media

    {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media_id}")

    assert html =~ html_escape(book_title)
  end
end
