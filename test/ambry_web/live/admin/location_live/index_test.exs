defmodule AmbryWeb.Admin.LocationLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Library

  setup :register_and_log_in_admin_user

  test "invites the operator to add the first location", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/locations")

    assert html =~ "No locations yet."
  end

  test "lists locations with their kind and path", %{conn: conn} do
    insert(:location, name: "Downloads NAS", path: "/data/downloads", kind: :downloads)

    insert(:location,
      name: "Old Library",
      path: "/data/library",
      kind: :library_root,
      import_policy: nil
    )

    {:ok, _view, html} = live(conn, ~p"/admin/locations")

    assert html =~ "Downloads NAS"
    assert html =~ "/data/downloads"
    assert html =~ "Downloads"
    assert html =~ "Old Library"
    assert html =~ "Library root"
  end

  # The whole reason this page exists: hardlinks can't cross a filesystem, and
  # you can't tell from two paths whether they share one.
  test "tags locations that share a filesystem with the same label", %{conn: conn} do
    insert(:location, name: "A", path: tmp_dir())
    insert(:location, name: "B", path: tmp_dir())

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    tags =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-role='location-filesystem']")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert tags == ["A", "A"]
  end

  test "says plainly when a location isn't there", %{conn: conn} do
    insert(:location, name: "Unmounted", path: "/mnt/not-mounted")

    {:ok, _view, html} = live(conn, ~p"/admin/locations")

    assert html =~ "Not found"
    assert html =~ "is the volume mounted?"
  end

  test "pauses and resumes a location", %{conn: conn} do
    location = insert(:location, enabled: true)

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    view |> element("[data-role='toggle-location']") |> render_click()
    refute Library.get_location!(location.id).enabled

    view |> element("[data-role='toggle-location']") |> render_click()
    assert Library.get_location!(location.id).enabled
  end

  # Removing a location is a registry edit, never a disk operation — for an
  # external collection, touching the files would break the only promise
  # external custody makes.
  test "deleting a location leaves its files alone", %{conn: conn} do
    dir = tmp_dir()
    file = Path.join(dir, "book.m4b")
    File.write!(file, "audio")
    location = insert(:location, path: dir)

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    html = view |> element("[data-role='delete-location']") |> render_click()

    assert html =~ "files were left alone"
    assert {:error, :not_found} = Library.fetch_location(location.id)
    assert File.exists?(file)
  end

  test "starts a scan of every enabled location", %{conn: conn} do
    insert(:location, path: tmp_dir())

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    html = view |> element("button[phx-click='scan']") |> render_click()

    assert html =~ "Scanning every enabled location"
  end

  defp tmp_dir do
    dir = Ambry.Paths.source_media_disk_path("locations-live-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
