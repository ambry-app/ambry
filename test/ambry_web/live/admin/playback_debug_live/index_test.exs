defmodule AmbryWeb.Admin.PlaybackDebugLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders list of playthroughs for a selected user", %{conn: conn} do
      user = insert(:user, email: "debug_user@example.com")
      book = insert(:book, title: "Test Book")
      media = insert(:media, book: book)

      insert(:playthrough,
        user: user,
        media: media,
        status: :in_progress,
        last_event_at: ~U[2023-01-02 10:00:00.000Z]
      )

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/playthroughs")

      assert html =~ "Playthroughs for debug_user@example.com"
      assert html =~ "Test Book"
      # The badge wears the status in words, not the schema atom (§8)
      assert html =~ "in progress"
    end

    test "clicking a playthrough opens the events modal", %{conn: conn} do
      user = insert(:user)
      book = insert(:book, title: "Modal Test Book")
      media = insert(:media, book: book)
      playthrough = insert(:playthrough, user: user, media: media)

      insert(:playback_event,
        playthrough_id: playthrough.id,
        type: :play,
        position: Decimal.new("123.4")
      )

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/playthroughs")

      # The whole card is a real link now, not a div carrying JS.patch
      view
      |> element("a[href*='#{playthrough.id}']")
      |> render_click()

      # Assert modal is shown and contains the event
      assert has_element?(view, "#events-modal")
      assert render(view) =~ "Playback Events"
      assert render(view) =~ "Modal Test Book"
      assert render(view) =~ "play"
      assert render(view) =~ "123.4"
    end
  end
end
