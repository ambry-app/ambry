defmodule AmbryWeb.AudiobookLivePartTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "shows the part label and group name on the audiobook page", %{conn: conn} do
    book = insert(:book, title: "Dungeon Crawler Carl")
    group = insert(:recording_group, name: "Season One", parts_total: 3)

    media =
      insert(:media,
        book: book,
        part_number: 2,
        recording_group: group,
        status: :ready
      )

    {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media.id}")

    assert html =~ "Dungeon Crawler Carl (Part 2 of 3)"
    assert html =~ "Part 2 of 3"
    refute html =~ "Season One"
  end

  test "tiles show composed titles for parts", %{conn: conn} do
    book = insert(:book, title: "The Way of Kings")
    group = insert(:recording_group, parts_total: 3)

    insert(:media, book: book, part_number: 1, recording_group: group, status: :ready)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "The Way of Kings (Part 1 of 3)"
  end
end
