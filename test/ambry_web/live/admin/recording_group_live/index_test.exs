defmodule AmbryWeb.Admin.RecordingGroupLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Media

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders group index with empty state when no groups exist", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/sets")

      assert html =~ "Sets"
      assert has_element?(view, "[data-role='empty-message']", "No sets yet.")
    end

    test "renders list of groups with their book and parts summary", %{conn: conn} do
      book = insert(:book, title: "A Court of Thorns and Roses")
      group = insert(:recording_group, name: "GraphicAudio", parts_total: 3, book: book)
      insert(:media, book: book, part_number: 1, recording_group: group)
      insert(:media, book: book, part_number: 2, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets")

      assert has_element?(view, "[data-role='group-name']", "GraphicAudio")
      assert has_element?(view, "[data-role='group-book']", "A Court of Thorns and Roses")
      assert has_element?(view, "[data-role='group-parts']", "2 of 3 parts")
    end

    test "the parts summary uses the group's own wording", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group, part_word_plural: "episodes")
      insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets")

      assert has_element?(view, "[data-role='group-parts']", "1 episodes")
    end

    test "updates list in realtime when groups change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sets")

      assert has_element?(view, "[data-role='empty-message']", "No sets yet.")

      book = insert(:book)
      {:ok, group} = Media.create_recording_group(%{name: "New Group", book_id: book.id})
      group |> Ambry.Media.PubSub.RecordingGroupCreated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='group-name']", "New Group")

      {:ok, group} = Media.update_recording_group(group, %{name: "Updated Group"})
      group |> Ambry.Media.PubSub.RecordingGroupUpdated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='group-name']", "Updated Group")
      refute has_element?(view, "[data-role='group-name']", "New Group")

      {:ok, _} = Media.delete_recording_group(group)
      group |> Ambry.Media.PubSub.RecordingGroupDeleted.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='empty-message']", "No sets yet.")
    end
  end

  describe "Delete" do
    test "deleting a group detaches members and clears their part numbers", %{conn: conn} do
      book = insert(:book)
      group = insert(:recording_group, name: "Delete Me")
      media = insert(:media, book: book, part_number: 1, recording_group: group)

      {:ok, view, _html} = live(conn, ~p"/admin/sets")

      assert has_element?(view, "[data-role='group-name']", "Delete Me")

      view
      |> element("[data-role='delete-group']")
      |> render_click()

      refute has_element?(view, "[data-role='group-name']", "Delete Me")
      assert has_element?(view, "[data-role='empty-message']", "No sets yet.")
      assert render(view) =~ "Deleted Delete Me."

      reloaded = Media.get_media!(media.id)
      assert reloaded.recording_group_id == nil
      assert reloaded.part_number == nil
    end
  end

  describe "Search" do
    test "filters groups by name", %{conn: conn} do
      insert(:recording_group, name: "Unique Group Name")
      insert(:recording_group, name: "Another Group")

      {:ok, view, _html} = live(conn, ~p"/admin/sets")

      assert has_element?(view, "[data-role='group-name']", "Unique Group Name")
      assert has_element?(view, "[data-role='group-name']", "Another Group")

      view
      |> form("[data-role='search-form']")
      |> render_submit(%{search: %{query: "Unique"}})

      assert has_element?(view, "[data-role='group-name']", "Unique Group Name")
      refute has_element?(view, "[data-role='group-name']", "Another Group")
    end
  end
end
