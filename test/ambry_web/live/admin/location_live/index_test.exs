defmodule AmbryWeb.Admin.LocationLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Library

  setup :register_and_log_in_admin_user

  test "invites the operator to add the first source", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/locations")

    assert html =~ "No sources yet"
  end

  # Roots are mandatory now: every import places into one.
  test "an empty roots section says imports need one", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/locations")

    assert html =~ "Nothing can be imported until there is one"
  end

  test "lists sources and roots as two sections", %{conn: conn} do
    insert(:source, name: "Downloads NAS", path: "/data/downloads")
    insert(:root, name: "Old Library", path: "/data/library")

    {:ok, _view, html} = live(conn, ~p"/admin/locations")

    assert html =~ "Downloads NAS"
    assert html =~ "/data/downloads"
    assert html =~ "hardlink"
    assert html =~ "Old Library"
    assert html =~ "/data/library"
  end

  # The whole reason this page exists: hardlinks can't cross a filesystem, and
  # you can't tell from two paths whether they share one.
  test "tags a source and a root sharing a filesystem with the same label", %{conn: conn} do
    insert(:source, name: "A", path: tmp_dir())
    insert(:root, name: "B", path: tmp_dir())

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    tags =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-role='source-filesystem'], [data-role='root-filesystem']")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert tags == ["A", "A"]
  end

  test "says plainly when a source isn't there", %{conn: conn} do
    insert(:source, name: "Unmounted", path: "/mnt/not-mounted")

    {:ok, _view, html} = live(conn, ~p"/admin/locations")

    assert html =~ "Not found"
    assert html =~ "Is the volume mounted?"
  end

  test "pauses and resumes a source", %{conn: conn} do
    source = insert(:source, enabled: true)

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    view |> element("[data-role='toggle-source']") |> render_click()
    refute Library.get_source!(source.id).enabled

    view |> element("[data-role='toggle-source']") |> render_click()
    assert Library.get_source!(source.id).enabled
  end

  # Removing a source or root is a registry edit, never a disk operation.
  test "deleting a source leaves its files alone", %{conn: conn} do
    dir = tmp_dir()
    file = Path.join(dir, "book.m4b")
    File.write!(file, "audio")
    source = insert(:source, path: dir)

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    html = view |> element("[data-role='delete-source']") |> render_click()

    assert html =~ "files were left alone"
    assert {:error, :not_found} = Library.fetch_source(source.id)
    assert File.exists?(file)
  end

  test "deleting a root leaves its files alone", %{conn: conn} do
    dir = tmp_dir()
    file = Path.join(dir, "book.m4b")
    File.write!(file, "audio")
    root = insert(:root, path: dir)

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    html = view |> element("[data-role='delete-root']") |> render_click()

    assert html =~ "files were left alone"
    assert {:error, :not_found} = Library.fetch_root(root.id)
    assert File.exists?(file)
  end

  test "starts a scan of every watched source", %{conn: conn} do
    insert(:source, path: tmp_dir())

    {:ok, view, _html} = live(conn, ~p"/admin/locations")

    html = view |> element("button[phx-click='scan']") |> render_click()

    assert html =~ "Scanning every watched source"
  end

  defp tmp_dir do
    dir = Ambry.Paths.source_media_disk_path("locations-live-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
