defmodule AmbryWeb.Admin.SettingsLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Settings

  setup :register_and_log_in_admin_user

  test "shows direct-play publishing off, with the reason", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    assert html =~ "Publish direct-play recordings"
    assert html =~ "can&#39;t be marked ready"
    assert html =~ "Turn on"
  end

  test "turns the switch on and back off", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    html = view |> element("button[phx-click='toggle-direct-play-publishing']") |> render_click()

    assert Settings.direct_play_publishing?()
    assert html =~ "Turn off"
    assert html =~ "can be made visible to clients"

    html = view |> element("button[phx-click='toggle-direct-play-publishing']") |> render_click()

    refute Settings.direct_play_publishing?()
    assert html =~ "Turn on"
  end
end
