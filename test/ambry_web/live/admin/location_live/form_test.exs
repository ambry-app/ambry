defmodule AmbryWeb.Admin.LocationLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Library

  setup :register_and_log_in_admin_user

  describe "new source" do
    test "adds a bring-in source", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/new")

      view
      |> form("#location-form",
        source: %{name: "Downloads NAS", path: "/data/downloads", on_import: "bring_in"}
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      assert [source] = Library.list_sources()
      assert source.name == "Downloads NAS"
      assert source.on_import == :bring_in
      assert source.import_policy == :hardlink
    end

    test "shows the placement details only when files are brought in", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/locations/sources/new")

      assert html =~ "How the files come in"

      html =
        view
        |> form("#location-form",
          source: %{name: "C", path: "/data/c", on_import: "leave_in_place"}
        )
        |> render_change()

      refute html =~ "How the files come in"
    end

    # Finding out that a path is wrong at save time is late; finding out at
    # scan time is far too late.
    test "checks the path as it's typed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/new")

      html =
        view
        |> form("#location-form",
          source: %{name: "S", path: tmp_dir(), on_import: "bring_in"}
        )
        |> render_change()

      assert html =~ "Folder found."

      html =
        view
        |> form("#location-form",
          source: %{name: "S", path: "/mnt/nope", on_import: "bring_in"}
        )
        |> render_change()

      assert html =~ "Nothing at that path right now"
    end

    test "refuses a relative path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/sources/new")

      html =
        view
        |> form("#location-form", source: %{name: "S", path: "data/s", on_import: "bring_in"})
        |> render_submit()

      assert html =~ "must be an absolute path"
      assert Library.list_sources() == []
    end
  end

  describe "new root" do
    test "adds a root, asking nothing but name and path", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/locations/roots/new")

      refute html =~ "On import"
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
      |> form("#location-form", source: %{name: "New Name", import_policy: "move"})
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      source = Library.get_source!(source.id)
      assert source.name == "New Name"
      assert source.import_policy == :move
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
  end

  defp tmp_dir do
    dir = Ambry.Paths.source_media_disk_path("locations-form-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
