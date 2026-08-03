defmodule AmbryWeb.Admin.LocationLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Library

  setup :register_and_log_in_admin_user

  describe "new" do
    test "adds a downloads location", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/new")

      view
      |> form("#location-form",
        location: %{name: "Downloads NAS", path: "/data/downloads", kind: "downloads"}
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      assert [location] = Library.list_locations()
      assert location.name == "Downloads NAS"
      assert location.kind == :downloads
      assert location.import_policy == :hardlink
    end

    test "shows the import policy only for downloads", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/locations/new")

      assert html =~ "On approval"

      html =
        view
        |> form("#location-form", location: %{name: "L", path: "/data/l", kind: "library_root"})
        |> render_change()

      refute html =~ "On approval"
    end

    # Finding out that a path is wrong at save time is late; finding out at
    # scan time is far too late.
    test "checks the path as it's typed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/new")

      html =
        view
        |> form("#location-form", location: %{name: "L", path: tmp_dir(), kind: "downloads"})
        |> render_change()

      assert html =~ "Folder found."

      html =
        view
        |> form("#location-form", location: %{name: "L", path: "/mnt/nope", kind: "downloads"})
        |> render_change()

      assert html =~ "Nothing at that path right now"
    end

    test "refuses a relative path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/locations/new")

      html =
        view
        |> form("#location-form", location: %{name: "L", path: "data/l", kind: "downloads"})
        |> render_submit()

      assert html =~ "must be an absolute path"
      assert Library.list_locations() == []
    end
  end

  describe "edit" do
    test "updates a location", %{conn: conn} do
      location = insert(:location, name: "Old Name")

      {:ok, view, _html} = live(conn, ~p"/admin/locations/#{location}/edit")

      view
      |> form("#location-form", location: %{name: "New Name", import_policy: "move"})
      |> render_submit()

      assert_redirect(view, ~p"/admin/locations")

      location = Library.get_location!(location.id)
      assert location.name == "New Name"
      assert location.import_policy == :move
    end
  end

  defp tmp_dir do
    dir = Ambry.Paths.source_media_disk_path("locations-form-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
