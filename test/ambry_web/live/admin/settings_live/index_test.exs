defmodule AmbryWeb.Admin.SettingsLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Library.NamingTemplate
  alias Ambry.Settings

  setup :register_and_log_in_admin_user

  describe "the search index" do
    test "says what it holds and that it is current", %{conn: conn} do
      insert(:book)
      insert_pair(:person)
      Ambry.Search.Drain.run()

      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert index_heading(html) == "3 records"
      assert html =~ "Up to date."
    end

    test "one record is not 1 records", %{conn: conn} do
      insert(:person)
      Ambry.Search.Drain.run()

      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert index_heading(html) == "1 record"
    end

    test "rebuilding queues the library and hands it to a job", %{conn: conn} do
      insert(:book)

      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      html = view |> element("button[phx-click='reindex']") |> render_click()

      assert html =~ "Rebuilding the search index in the background"
      # Not drained inline: a library of any size is minutes of work, and a
      # button that blocks until it is done is a button that times out.
      assert_enqueued(worker: Ambry.Search.RunDrain)
    end

    test "a queue that has not drained says so", %{conn: conn} do
      insert(:book)
      :ok = Ambry.Search.Queue.enqueue_all!()

      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Catching up on 1 change."
    end
  end

  test "shows direct-play publishing off, with the reason", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    assert html =~ "Publish direct-play audiobooks"
    assert html =~ "stay unpublished"
    assert html =~ "Turn on"
  end

  test "turns the switch on and back off", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    html = view |> element("button[phx-click='toggle-direct-play-publishing']") |> render_click()

    assert Settings.direct_play_publishing?()
    assert html =~ "Turn off"
    assert html =~ "can be published"

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

      assert html =~ "can&#39;t contain .."
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

  # The count and its word are two interpolations with HEEx whitespace
  # between them, so this reads the rendered text rather than the markup.
  defp index_heading(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='index-records']")
    |> Enum.map(&(&1 |> Floki.text() |> String.split() |> Enum.join(" ")))
    |> Enum.find(&(&1 =~ "record"))
  end
end
