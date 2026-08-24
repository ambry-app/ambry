defmodule AmbryWeb.Admin.LocationLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Library

  setup :register_and_log_in_admin_user

  describe "new source" do
    test "adds a source", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/new")

      view
      |> form("#location-form",
        source: %{name: "Downloads NAS", path: "/data/downloads"}
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      assert [source] = Library.list_sources()
      assert source.name == "Downloads NAS"
    end

    # A source is a path and nothing else. How its files reach the library
    # is a fact about the pairing with a root, decided per import and
    # remembered there — asking it here could only ever be right for one
    # destination.
    test "asks nothing about placement", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/locations/sources/new")

      refute html =~ "How the files come in"
      refute html =~ "Preferred library root"
    end

    # Finding out that a path is wrong at save time is late; finding out at
    # scan time is far too late.
    test "checks the path as it's typed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/new")

      html =
        view
        |> form("#location-form",
          source: %{name: "S", path: tmp_dir()}
        )
        |> render_change()

      assert html =~ "Folder found."

      html =
        view
        |> form("#location-form",
          source: %{name: "S", path: "/mnt/nope"}
        )
        |> render_change()

      assert html =~ "Nothing at that path right now"
    end

    test "refuses a relative path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/new")

      html =
        view
        |> form("#location-form", source: %{name: "S", path: "data/s"})
        |> render_submit()

      assert html =~ "must be an absolute path"
      assert Library.list_sources() == []
    end
  end

  describe "new root" do
    test "adds a root, asking nothing but name and path", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/locations/roots/new")

      refute html =~ "How the files come in"
      refute html =~ "Watched"

      view
      |> form("#location-form", root: %{name: "Library", path: "/data/library"})
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      assert [root] = Library.list_roots()
      assert root.name == "Library"
      assert root.path == "/data/library"
    end
  end

  describe "edit" do
    test "updates a source", %{conn: conn} do
      source = insert(:source, name: "Old Name")

      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/#{source}/edit")

      view
      |> form("#location-form", source: %{name: "New Name"})
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      source = Library.get_source!(source.id)
      assert source.name == "New Name"
    end

    test "updates a root", %{conn: conn} do
      root = insert(:root, name: "Old Name")

      {:ok, view, _html} = live(conn, ~p"/admin/locations/roots/#{root}/edit")

      view
      |> form("#location-form", root: %{name: "New Name"})
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      assert Library.get_root!(root.id).name == "New Name"
    end

    # Both homes a delete has, per §6: the row in the list, and this bar.
    test "removes a source from the sticky footer", %{conn: conn} do
      source = insert(:source, name: "Old Downloads")

      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/#{source}/edit")

      view |> element("[data-role='delete-source']") |> render_click()

      assert_redirect(view, ~p"/admin/locations")
      assert Library.list_sources() == []
    end

    test "removing says the files were left alone", %{conn: conn} do
      root = insert(:root, name: "Old Root")

      {:ok, view, _html} = live(conn, ~p"/admin/locations/roots/#{root}/edit")

      view |> element("[data-role='delete-root']") |> render_click()

      assert %{"info" => message} = assert_redirect(view, ~p"/admin/locations")
      assert message == "Removed Old Root. Its files were left alone."
    end

    test "a root the library still serves from cannot be removed", %{conn: conn} do
      root = insert(:root)
      media = insert(:media, book: build(:book), mpd_path: nil, hls_path: nil, mp4_path: nil)
      insert(:media_track, media: media, library_root_id: root.id, path: "Some Book/track.m4b")

      {:ok, view, _html} = live(conn, ~p"/admin/locations/roots/#{root}/edit")

      html = view |> element("[data-role='delete-root']") |> render_click()

      # Named as files, not as recordings: nothing here is a recording, and
      # the message used to say "still holds 0 recordings".
      assert html =~ "still holds 1 audio file"
      assert html =~ "has to outlive them"
      assert Library.get_root!(root.id)
    end
  end

  # A record that does not exist yet cannot be destroyed, so the bar does not
  # offer it.
  describe "a new location" do
    test "offers no remove", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/new")

      refute has_element?(view, "[data-role='delete-source']")
    end
  end

  defp tmp_dir do
    dir = Ambry.Paths.source_media_disk_path("locations-form-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
