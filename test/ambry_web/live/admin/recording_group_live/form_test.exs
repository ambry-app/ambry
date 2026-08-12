defmodule AmbryWeb.Admin.RecordingGroupLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Media

  setup :register_and_log_in_admin_user

  describe "New" do
    test "creates a group with members, exactly like a series with books", %{conn: conn} do
      book = insert(:book)
      media_one = insert(:media, book: book)
      media_two = insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/new")

      view
      |> form("#group-form")
      |> render_submit(%{
        recording_group_form: %{
          name: "Season One",
          book_id: to_string(book.id),
          parts_total: "2",
          part_word: "episode",
          members: %{
            "0" => %{media_id: to_string(media_one.id), part_number: "1"},
            "1" => %{media_id: to_string(media_two.id), part_number: "2"}
          }
        }
      })

      assert_redirect(view, "/admin/sets")

      {[group], false} = Media.list_recording_groups()
      assert %{name: "Season One", parts_total: 2, part_word: "episode"} = group

      assert Enum.map(group.media, &{&1.id, &1.part_number}) ==
               [{media_one.id, 1}, {media_two.id, 2}]
    end

    test "a group may start empty", %{conn: conn} do
      book = insert(:book)
      {:ok, view, _html} = live(conn, ~p"/admin/sets/new")

      view
      |> form("#group-form")
      |> render_submit(%{
        recording_group_form: %{name: "Awaiting Parts", book_id: to_string(book.id)}
      })

      assert_redirect(view, "/admin/sets")

      {[group], false} = Media.list_recording_groups()
      assert %{name: "Awaiting Parts", media: []} = group
    end

    test "refuses a blank name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sets/new")

      html =
        view
        |> form("#group-form")
        |> render_submit(%{recording_group_form: %{name: ""}})

      assert html =~ "can&#39;t be blank"
      assert Media.count_recording_groups() == 0
    end
  end

  describe "Edit" do
    test "renders existing members as editable rows", %{conn: conn} do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "GraphicAudio", parts_total: 2, book: book)
      media = insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, _view, html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      doc = Floki.parse_document!(html)

      assert doc
             |> Floki.find(~s{input[name="recording_group_form[members][0][part_number]"]})
             |> Floki.attribute("value") == ["1"]

      assert doc
             |> Floki.find(~s{input[name="recording_group_form[members][0][media_id]"]})
             |> Floki.attribute("value") == [to_string(media.id)]
    end

    # Regression: validate re-derives member options from the posted book_id,
    # but the edit page renders the book as static text (posts nothing) — so
    # any keystroke in any field emptied the options, and every member
    # typeahead displayed blank (its label lookup by id found nothing).
    test "editing another field leaves the member typeaheads displaying their picks", %{
      conn: conn
    } do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "Graphic Audio", book: book)
      insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, view, html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      assert resolver_display(html) == "A Court of Thorns and Roses"

      html =
        view
        |> form("#group-form")
        |> render_change(%{recording_group_form: %{name: "Renamed"}})

      assert resolver_display(html) == "A Court of Thorns and Roses"
    end

    test "saving edits facts and the member list together", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group, name: "Before", book: book)
      keep = insert(:media, book: book, part_number: 1, recording_group: group)
      drop = insert(:media, book: book, part_number: 2, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group.id}/edit")

      # removal is the drop checkbox, same mechanics as dropping a series book
      view
      |> form("#group-form")
      |> render_submit(%{
        recording_group_form: %{
          name: "After",
          show_label: "true",
          members_drop: ["1"]
        }
      })

      assert_redirect(view, "/admin/sets")

      updated = Media.get_recording_group!(group.id)
      assert %{name: "After", show_label: true} = updated
      assert Enum.map(updated.media, & &1.id) == [keep.id]

      dropped = Media.get_media!(drop.id)
      assert dropped.recording_group_id == nil
      assert dropped.part_number == nil
    end
  end

  defp resolver_display(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s{input[name="resolver[recording_group_form_members_0_media_id]"]})
    |> Floki.attribute("value")
    |> List.first()
  end
end
