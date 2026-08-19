defmodule AmbryWeb.Admin.MediaLive.SetPickerTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "the \"Part of a set\" picker" do
    # The first audiobook of a book is the common case, and it is the one
    # where the picker has nothing to offer: the book has no sets yet.
    test "opens with an empty option list instead of crashing", %{conn: conn} do
      media = insert(:media, book: insert(:book))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      view |> element("button[phx-click='add-group-row']") |> render_click()

      html = view |> element("#media_recording_group_id-trigger") |> render_click()

      assert html =~ "Nothing to choose from"
      # a drop-down never offers to invent a record
      refute html =~ "Create “"
    end

    # An empty inline span is a flex item with no line box, so an empty
    # drop-down collapsed to its own padding and stood two-thirds the height
    # of the number field beside it.
    test "holding nothing, it still stands as tall as a field of text", %{conn: conn} do
      media = insert(:media, book: insert(:book))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      html = view |> element("button[phx-click='add-group-row']") |> render_click()

      label =
        html
        |> Floki.parse_document!()
        |> Floki.find("#media_recording_group_id-trigger span")
        |> Floki.text()

      assert label != ""
    end

    # An action meaning "remove this row" belongs beside the field, not on top
    # of one: it removes the row rather than the field's value, and a mark
    # inside a box reads as belonging to that box. It also collided — the
    # ✕ was positioned exactly where the drop-down's chevron draws.
    test "the row's ✕ sits beside the picker, not inside it", %{conn: conn} do
      media = insert(:media, book: insert(:book))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      html = view |> element("button[phx-click='add-group-row']") |> render_click()
      doc = Floki.parse_document!(html)

      assert Floki.find(doc, "#media_recording_group_id button[phx-click='remove-group-row']") ==
               []

      assert Floki.find(doc, "button[phx-click='remove-group-row']") != []
    end

    test "offers the book's sets, and only those", %{conn: conn} do
      book = insert(:book)
      insert(:recording_group, book: book, name: "Graphic Audio")
      insert(:recording_group, book: insert(:book), name: "Some Other Book's Set")
      media = insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      view |> element("button[phx-click='add-group-row']") |> render_click()

      html = view |> element("#media_recording_group_id-trigger") |> render_click()

      assert html =~ "Graphic Audio"
      refute html =~ "Some Other Book&#39;s Set"
    end

    test "puts an audiobook in a set by clicking one", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group, book: book, name: "Graphic Audio")
      media = insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      view |> element("button[phx-click='add-group-row']") |> render_click()
      view |> element("#media_recording_group_id-trigger") |> render_click()

      html =
        view
        |> element("#media_recording_group_id-option-#{group.id}")
        |> render_click()

      # The trigger now says what it holds, the way a closed select does.
      assert html =~ "Graphic Audio"
    end

    # Hiding the row stopped the form *mentioning* the set rather than saying
    # it was gone, and `cast` only changes the keys it is handed — so the
    # picker vanished, Save reported success, and the recording came back
    # still in its set.
    test "taking an audiobook out of a set sticks", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group, book: book, name: "Graphic Audio")
      media = insert(:media, book: book, recording_group: group, part_number: 2)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      view |> element("button[phx-click='remove-group-row']") |> render_click()

      view |> form("#media-form") |> render_submit()

      reloaded = Ambry.Media.get_media!(media.id)

      assert reloaded.recording_group_id == nil
      assert reloaded.part_number == nil
    end
  end
end
