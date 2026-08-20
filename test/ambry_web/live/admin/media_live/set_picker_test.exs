defmodule AmbryWeb.Admin.MediaLive.SetPickerTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "the \"Part of a set\" picker" do
    # The first audiobook of a book is the common case, and it is the one
    # where the picker has nothing to offer: the book has no sets yet. It
    # used to open an empty drop-down and say so; now there is nothing to
    # drop down to and the only thing to do is name a set, so that is what
    # it offers. (`EntityDropdown`'s empty state still exists and is still
    # reachable from the set form's book picker.)
    test "with no sets to join, it goes straight to naming one", %{conn: conn} do
      media = insert(:media, book: insert(:book))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      html = view |> element("button[phx-click='add-group-row']") |> render_click()

      refute html =~ "media_recording_group_id-trigger"
      assert html =~ "set name"
      assert has_element?(view, "input[name='media[recording_group][name]']")
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

  # A set was the one entity on this form that had to be made somewhere else
  # first: the drop-down could only ever join one (`EDIT_PARITY_PLAN.md`
  # phase 5).
  describe "naming a set the book doesn't have" do
    test "the save makes it, on the recording's own book", %{conn: conn} do
      book = insert(:book)
      media = insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
      view |> element("button[phx-click='add-group-row']") |> render_click()

      view
      |> form("#media-form")
      |> render_submit(%{
        "media" => %{
          "part_number" => "1",
          "recording_group_id" => "",
          "recording_group" => %{"name" => "Graphic Audio", "parts_total" => "3"}
        }
      })

      reloaded = Ambry.Media.get_media!(media.id)
      group = Ambry.Repo.get!(Ambry.Media.RecordingGroup, reloaded.recording_group_id)

      assert group.name == "Graphic Audio"
      assert group.parts_total == 3
      # never asked for, never postable: a set belongs to a book the way its
      # members do
      assert group.book_id == book.id
      assert reloaded.part_number == 1
    end

    test "a set with no name is refused, and nothing is created", %{conn: conn} do
      media = insert(:media, book: insert(:book))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
      view |> element("button[phx-click='add-group-row']") |> render_click()

      view
      |> form("#media-form")
      |> render_submit(%{
        "media" => %{
          "part_number" => "1",
          "recording_group_id" => "",
          "recording_group" => %{"name" => ""}
        }
      })

      assert Ambry.Repo.aggregate(Ambry.Media.RecordingGroup, :count) == 0
      assert Ambry.Media.get_media!(media.id).part_number == nil
    end

    # Moving from one set to a new one is not leaving one: the id blanks,
    # which is also how "leaving" reads, and the part number used to be
    # cleared out from under the operator.
    test "switching a recording from its set to a new one keeps the part number",
         %{conn: conn} do
      book = insert(:book)
      old_group = insert(:recording_group, book: book, name: "Graphic Audio")
      media = insert(:media, book: book, recording_group: old_group, part_number: 2)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      view
      |> form("#media-form")
      |> render_submit(%{
        "media" => %{
          "part_number" => "2",
          "recording_group_id" => "",
          "recording_group" => %{"name" => "Season One"}
        }
      })

      reloaded = Ambry.Media.get_media!(media.id)

      assert reloaded.part_number == 2
      assert reloaded.recording_group_id != old_group.id

      assert Ambry.Repo.get!(Ambry.Media.RecordingGroup, reloaded.recording_group_id).name ==
               "Season One"
    end

    # Choosing an existing set from the drop-down is still a link, and the
    # name box has no business posting a second set beside it.
    test "picking an existing set creates nothing", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group, book: book, name: "Graphic Audio")
      media = insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
      view |> element("button[phx-click='add-group-row']") |> render_click()

      view
      |> form("#media-form")
      |> render_submit(%{
        "media" => %{
          "part_number" => "2",
          "recording_group_id" => to_string(group.id),
          "recording_group" => %{"name" => "Something else entirely"}
        }
      })

      assert Ambry.Repo.aggregate(Ambry.Media.RecordingGroup, :count) == 1
      assert Ambry.Media.get_media!(media.id).recording_group_id == group.id
      assert Ambry.Repo.get!(Ambry.Media.RecordingGroup, group.id).name == "Graphic Audio"
    end
  end
end
