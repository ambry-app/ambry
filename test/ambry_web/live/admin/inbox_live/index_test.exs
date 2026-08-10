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

  # One button, because the two it replaced were never separable: matching
  # leans on the tags the probe produces, so asking again without re-reading
  # asks the same question of the same cache.
  test "re-reads and re-queries an item", %{conn: conn} do
    item = probed_item()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='rescan'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "Re-reading the files and asking the providers again"

    # `refresh` is what makes the difference between this and the old button:
    # it re-walks the folder and bypasses the 30-day provider cache, which the
    # rest of the chain reads off the job's args.
    assert_enqueued(
      worker: Ambry.Inbox.RunProbe,
      args: %{inbox_item_id: item.id, refresh: true}
    )
  end

  # An imported item's draft is the record of what was imported; re-matching
  # would rebuild it. The row keeps Open-by-title for looking, loses the
  # actions that write.
  test "an imported item's row offers no re-match", %{conn: conn} do
    item = probed_item() |> settle()
    {:ok, _media} = Ambry.Inbox.approve_item(item)

    {:ok, view, _html} = live(conn, ~p"/admin/inbox?status=approved")

    refute has_element?(view, "span[phx-click='rescan'][phx-value-id='#{item.id}']")
  end

  # `RunMatch` is unique over a 60-second window and Oban answers a conflict
  # with `{:ok, %{job | conflict?: true}}` — an insert that looks successful
  # and drops the job. The old handler matched `{:ok, _job}` and flashed
  # success either way, which is how "look for matches again" came to do
  # nothing at all.
  test "a re-query is not silently swallowed by the uniqueness window", %{conn: _conn} do
    item = probed_item()

    {:ok, item} = Inbox.rescan_item(item)

    assert_enqueued(
      worker: Ambry.Inbox.RunMatch,
      args: %{inbox_item_id: item.id, refresh: true}
    )

    # a second one goes through too, rather than colliding with the first
    {:ok, _item} = Inbox.rescan_item(item)

    assert 2 ==
             Enum.count(
               all_enqueued(worker: Ambry.Inbox.RunMatch),
               &(&1.args["refresh"] == true)
             )
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

    # the default view is pending, so the dismissed item has left it
    refute has_element?(view, "span[phx-click='restore'][phx-value-id='#{item.id}']")

    {:ok, view, _html} = live(conn, ~p"/admin/inbox?status=dismissed")

    view |> element("span[phx-click='restore'][phx-value-id='#{item.id}']") |> render_click()

    assert Inbox.get_item!(item.id).status == :pending
  end

  test "approves a settled item into the library, leaving files alone", %{conn: conn} do
    item = probed_item() |> settle()
    file = hd(item.files)

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='approve'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "Files were left where they are"
    assert %{status: :approved, media_id: media_id} = Inbox.get_item!(item.id)
    assert media_id
    assert File.exists?(file)
  end

  # The queue can't say *what* is outstanding, so it doesn't offer a button
  # that would fail — it sends you to the form, which can.
  test "an unsettled item offers the form rather than an import button", %{conn: conn} do
    item = probed_item()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    refute has_element?(view, "span[phx-click='approve'][phx-value-id='#{item.id}']")
    assert has_element?(view, "a[href='/admin/inbox/#{item.id}']")
  end

  test "a refusal no curation can fix is visible before anything is clicked", %{conn: conn} do
    item = probed_item(files: ["01.mp3", "02.mp3"])

    {:ok, view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "direct play handles single-file recordings"
    refute has_element?(view, "span[phx-click='approve'][phx-value-id='#{item.id}']")
    assert Inbox.get_item!(item.id).status == :pending
  end

  test "the ready bucket counts what is waiting on a click", %{conn: conn} do
    ready = probed_item(name: "Settled") |> settle()
    _outstanding = probed_item(name: "Outstanding")

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html = view |> element("span[data-role='ready-filter']") |> render_click()

    assert html =~ "Settled"
    refute html =~ "Outstanding"
    assert Inbox.count_ready() == 1
    # the flag is stored, not recomputed per render — that's what lets the
    # bucket be a plain SQL filter
    assert Inbox.get_item!(ready.id).ready
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

  # Every row the inbox does work on gets covered, for the same reason the
  # form does: a job is about to change it, and a row that looks readable but
  # is about to be rewritten invites a click that goes nowhere.
  describe "rows a job is working on" do
    test "a queued row is covered and inert", %{conn: conn} do
      # discovery enqueues the match job, so a fresh item has one
      _item = probed_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox")

      assert has_element?(view, "[data-role='busy-overlay']")
      assert html =~ "Queued"
      assert html =~ "inert"
    end

    test "a row with nothing working on it is not covered", %{conn: conn} do
      _item = probed_item()
      Ambry.Repo.delete_all(Oban.Job)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox")

      refute has_element?(view, "[data-role='busy-overlay']")
    end

    test "the cover comes off once the job is gone", %{conn: conn} do
      _item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox")
      assert has_element?(view, "[data-role='busy-overlay']")

      Ambry.Repo.delete_all(Oban.Job)
      send(view.pid, :refresh_progress)
      render(view)

      refute has_element?(view, "[data-role='busy-overlay']")
    end
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
