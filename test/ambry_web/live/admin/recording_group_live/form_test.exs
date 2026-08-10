defmodule AmbryWeb.Admin.RecordingGroupLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Media

  setup :register_and_log_in_admin_user

  describe "New" do
    test "creates a group, which may start empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/groups/new")

      view
      |> form("#group-form")
      |> render_submit(%{
        recording_group: %{name: "Season One", parts_total: "3", part_word: "episode"}
      })

      assert_redirect(view, "/admin/groups")

      {[group], false} = Media.list_recording_groups()
      assert %{name: "Season One", parts_total: 3, part_word: "episode", media: []} = group
    end

    test "refuses a blank name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/groups/new")

      html =
        view
        |> form("#group-form")
        |> render_submit(%{recording_group: %{name: ""}})

      assert html =~ "can&#39;t be blank"
      assert Media.count_recording_groups() == 0
    end
  end

  describe "Edit" do
    test "edits set-level facts and lists members with part labels", %{conn: conn} do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "GraphicAudio", parts_total: 2)
      media = insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, view, html} = live(conn, ~p"/admin/groups/#{group.id}/edit")

      member =
        html
        |> Floki.parse_document!()
        |> Floki.find("[data-role='group-member']")
        |> Floki.text()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      assert member == "Part 1 of 2 — A Court of Thorns and Roses"
      assert html =~ ~p"/admin/media/#{media}/edit"

      view
      |> form("#group-form")
      |> render_submit(%{recording_group: %{name: "GraphicAudio Set", show_label: "true"}})

      assert_redirect(view, "/admin/groups")

      updated = Media.get_recording_group!(group.id)
      assert %{name: "GraphicAudio Set", show_label: true} = updated
    end
  end
end
