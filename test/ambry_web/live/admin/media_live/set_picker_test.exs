defmodule AmbryWeb.Admin.MediaLive.SetPickerTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "the \"Part of a set\" picker" do
    # The first audiobook of a book is the common case, and it is the one
    # where the picker has nothing to offer: the book has no sets yet, so
    # the option list is empty and the list's empty state is what renders.
    # That branch read `not (@text_name && ...)`, and `text_name` is nil in
    # a pure picker — `:erlang.not(nil)` took the LiveView down before the
    # operator could type anything.
    test "opens with an empty option list instead of crashing", %{conn: conn} do
      media = insert(:media, book: insert(:book))

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      view |> element("button[phx-click='add-group-row']") |> render_click()

      html = view |> element("#media_recording_group_id-input") |> render_focus()

      assert html =~ "No matches"
      # a pure picker never offers to invent a record
      refute html =~ "Create “"
    end

    test "opens with an empty option list after filtering everything out", %{conn: conn} do
      book = insert(:book)
      insert(:recording_group, book: book, name: "Unabridged")
      media = insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")

      view |> element("button[phx-click='add-group-row']") |> render_click()

      html =
        view
        |> element("#media_recording_group_id-input")
        |> render_change(%{"resolver" => %{"media_recording_group_id" => "zzzz"}})

      assert html =~ "No matches"
    end
  end
end
