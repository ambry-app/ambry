defmodule AmbryWeb.Admin.InboxLive.IndexTest do
  use AmbryWeb.ConnCase, async: true
  use Oban.Testing, repo: Ambry.Repo

  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Inbox.RunDiscovery

  setup :register_and_log_in_admin_user

  test "says so when there's nothing waiting", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "Nothing waiting"
  end

  test "shows what a candidate is and what it claims to be", %{conn: conn} do
    item = probed_item()

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "The Way of Kings [M4B]"
    assert html =~ item.path
    # the claims
    assert html =~ "Sanderson"
    # the facts
    assert html =~ "aac"
    assert html =~ "pending"
  end

  test "surfaces an issue rather than hiding the item", %{conn: conn} do
    item = probed_item(files: ["01.mp3", "02.mp3"])

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "2 audio files"
    assert html =~ item.path
  end

  test "shows both matches with how sure each one is", %{conn: conn} do
    item = probed_item()

    {:ok, _item} =
      Inbox.update_item(item, %{
        matches: %{
          "work" => %{
            "confidence" => 0.95,
            "query" => "The Way of Kings",
            "candidates" => [
              %{
                "title" => "The Way of Kings",
                "authors" => ["Brandon Sanderson"],
                "source" => "local"
              },
              %{"title" => "The Way of Kings Prime", "authors" => [], "source" => "provider:x"}
            ]
          },
          "recording" => %{"confidence" => 0.0, "query" => nil, "candidates" => []}
        }
      })

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "near-certain"
    assert html =~ "The Way of Kings"
    assert html =~ "already in library"
    assert html =~ "+1 other"
    # the recording level says so rather than going silent
    assert html =~ "no match"
  end

  test "asks for a fresh match", %{conn: conn} do
    item = probed_item()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='rematch'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "Looking for matches again"
    assert_enqueued(worker: Ambry.Inbox.RunMatch, args: %{inbox_item_id: item.id})
  end

  test "starts a scan", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html = view |> element("button[phx-click='scan']") |> render_click()

    assert html =~ "Nothing is moved or changed"
    assert_enqueued(worker: RunDiscovery)
  end

  test "dismisses and restores without touching files", %{conn: conn} do
    item = probed_item()
    file = hd(item.files)

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='dismiss'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "Files untouched"
    assert Inbox.get_item!(item.id).status == :dismissed
    assert File.exists?(file)

    view |> element("span[phx-click='restore'][phx-value-id='#{item.id}']") |> render_click()

    assert Inbox.get_item!(item.id).status == :pending
  end

  test "approves an item into the library, leaving files alone", %{conn: conn} do
    item = probed_item()
    file = hd(item.files)

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='approve'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "Files were left where they are"
    assert %{status: :approved, media_id: media_id} = Inbox.get_item!(item.id)
    assert media_id
    assert File.exists?(file)
  end

  test "explains a refusal instead of failing silently", %{conn: conn} do
    item = probed_item(files: ["01.mp3", "02.mp3"])

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='approve'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "single-file recordings"
    assert Inbox.get_item!(item.id).status == :pending
  end

  test "filters by status", %{conn: conn} do
    keeper = probed_item(name: "Keeper")
    reject = probed_item(name: "Reject")
    {:ok, _item} = Inbox.dismiss_item(reject)

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html = view |> element("span[phx-value-status='pending']") |> render_click()

    assert html =~ "Keeper"
    refute html =~ "Reject"
    assert Inbox.get_item!(keeper.id).status == :pending
  end

  defp probed_item(opts \\ []) do
    name = Keyword.get(opts, :name, "The Way of Kings [M4B]")
    files = Keyword.get(opts, :files, ["book.m4b"])

    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    release = Path.join(root, name)
    File.mkdir_p!(release)

    Enum.each(files, fn filename ->
      fixture = if Path.extname(filename) == ".mp3", do: valid_audio(:mp3), else: tagged_fixture()
      File.cp!(fixture, Path.join(release, filename))
    end)

    {:ok, _counts} = Inbox.discover(root)

    {items, _more} = Inbox.list_items(filter: name)
    item = hd(items)
    {:ok, item} = Inbox.probe_item(item)
    item
  end

  # Inside its own folder, never loose in source_media/ — the file audit
  # lists that directory and expects only folders.
  defp tagged_fixture do
    dir = Ambry.Paths.source_media_disk_path("tagged-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "tagged.m4b")

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "quiet",
        "-i",
        valid_audio(:m4a),
        "-c",
        "copy",
        "-metadata",
        "album=The Way of Kings",
        "-metadata",
        "artist=Brandon Sanderson",
        "-metadata",
        "date=2010-08-31",
        path
      ])

    path
  end
end
