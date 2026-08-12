defmodule AmbryWeb.Admin.SettingsLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Library.NamingTemplate
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

  describe "library naming template" do
    test "previews the default against a worked example", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert preview(html) ==
               "Brandon Sanderson/The Stormlight Archive/1 - The Way of Kings (2010)/" <>
                 "The Way of Kings [7bKq].m4b"
    end

    test "previews an edited template as it's typed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#naming-template-form", settings: %{template: "{author}/{title}"})
        |> render_change()

      assert preview(html) == "Brandon Sanderson/The Way of Kings/The Way of Kings [7bKq].m4b"
    end

    test "saves a valid template", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      view
      |> form("#naming-template-form", settings: %{template: "{author}/{title} ({year})"})
      |> render_submit()

      assert Settings.library_naming_template() == "{author}/{title} ({year})"
    end

    # A template's failure mode is a folder tree you don't notice is wrong
    # until it's already full of files, so the preview has to say why rather
    # than going blank.
    test "explains an invalid template instead of previewing it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#naming-template-form", settings: %{template: "{author}/{publisher}"})
        |> render_change()

      assert preview(html) =~ "there's no {publisher} token"
    end

    test "refuses a template that would escape the library root", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#naming-template-form", settings: %{template: "../{title}"})
        |> render_submit()

      assert html =~ "climb out of the root"
      assert Settings.library_naming_template() == NamingTemplate.default_template()
    end
  end

  defp preview(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='template-preview']")
    |> Floki.text()
    |> String.trim()
  end
end
