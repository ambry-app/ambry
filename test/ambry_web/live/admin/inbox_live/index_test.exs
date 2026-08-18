defmodule AmbryWeb.Admin.InboxLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Inbox.RunDiscovery
  alias Ambry.Inbox.RunImport

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
    # and what it still owes, which is the row's one badge. Nothing has
    # matched this yet, so there are no decisions to count — the badge says
    # that rather than inventing one.
    assert item_states(html) == ["not prepared"]
  end

  @tag :capture_log
  test "surfaces an issue rather than hiding the item", %{conn: conn} do
    item = probed_item(files: ["book.m4b"], unreadable: true)

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "couldn&#39;t read the file"
    assert html =~ item.path
  end

  # The overview's issue count used to link at the bare queue, which showed
  # every pending item and named none of them — the number was clickable and
  # still unanswerable.
  test "shows only the items the overview counted, and says so", %{conn: conn} do
    trouble = probed_item(name: "Trouble [M4B]", files: ["book.m4b"], unreadable: true)
    fine = probed_item(name: "Fine [M4B]")

    {:ok, view, html} = live(conn, ~p"/admin/inbox?problem=issue&status=pending")

    assert html =~ "Queue items with an issue"
    assert html =~ trouble.path
    refute html =~ fine.path

    # An issue narrows the tab rather than replacing it, so leaving the
    # filter keeps the operator where they were.
    way_out = view |> element("a[data-role='problem-filter']") |> render()
    assert way_out =~ "status=pending"
    refute way_out =~ "problem=issue"
  end

  test "a problem list that comes up dry says which list is empty", %{conn: conn} do
    _fine = probed_item(name: "Fine [M4B]")

    {:ok, _view, html} = live(conn, ~p"/admin/inbox?problem=issue&status=pending")

    assert html =~ "Nothing here is carrying an issue."
    refute html =~ "Nothing waiting"
  end

  test "counts a multi-file release's files on the row", %{conn: conn} do
    _item = probed_item(files: ["01.mp3", "02.mp3"])

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "files"
    assert html =~ ">2</span> files"
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

    # no draft yet, so the badge falls back to the match-time confidence
    assert html =~ "matched"
    assert html =~ "The Way of Kings"
    assert html =~ "already in the library"
    assert html =~ "+1 other"
    # the recording level says so rather than going silent
    assert html =~ "needs you"
  end

  # The badge is decision state, not match history: confidence was frozen at
  # match time, so the queue kept saying the operator was needed after they
  # had answered. Same four words as the form's rail, or the two drift.
  test "a level the operator settled stops asking for them", %{conn: conn} do
    record = %{
      "title" => "The Way of Kings",
      "authors" => ["Brandon Sanderson"],
      "source" => "provider:hardcover",
      "id" => "hc-1",
      "score" => 0.5
    }

    item = probed_item()

    {:ok, item} =
      Inbox.update_item(item, %{
        matches: %{
          "work" => %{"confidence" => 0.3, "query" => "q", "candidates" => [record]},
          "recording" => %{"confidence" => 0.0, "query" => nil, "candidates" => []},
          "people" => %{}
        }
      })

    {:ok, item} = Inbox.prepare_draft(item)

    {:ok, _view, html} = live(conn, ~p"/admin/inbox")
    assert html =~ "needs you"

    draft = Ambry.Inbox.Draft.Edit.toggle_source(item.draft, item, :work, record)
    {:ok, _item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

    # No longer waiting on the operator. It does not jump straight to
    # "reviewed": the row reads worst-first over the whole level, and the
    # identity question ("a book you already have?") is still one the machine
    # answered and nobody has looked at.
    {:ok, _view, html} = live(conn, ~p"/admin/inbox")
    refute html =~ ">needs you<"
    assert html =~ "matched"
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

  # The overlay reads `@progress`, which was only ever loaded with the page —
  # so the row the operator had just handed to a job went on looking idle and
  # clickable until they refreshed, by which time the slow part was over.
  test "the row is covered as soon as it's handed to a job", %{conn: conn} do
    item = probed_item()
    # discovery's own jobs, so the row starts uncovered
    Ambry.Repo.delete_all(Oban.Job)

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")
    refute has_element?(view, "[data-role='busy-overlay']")

    view |> element("span[phx-click='rescan'][phx-value-id='#{item.id}']") |> render_click()

    assert has_element?(view, "[data-role='busy-overlay']")
  end

  # The page links used to be built from the shared filter+page helpers,
  # which drop the status — so paging through "Imported" silently landed
  # back on the default pending view.
  test "the page links keep the status filter", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/inbox?status=ignored&page=2")

    assert view
           |> element("a[href*='status=ignored'][href*='page=1']")
           |> has_element?()
  end

  # The rail's shape and the order of its buttons used to change from row to
  # row as Import appeared and disappeared, which moved the primary action
  # under the cursor while the operator worked down the list.
  test "Import holds its place on a row that isn't settled yet", %{conn: conn} do
    {:ok, _item} = probed_item() |> Inbox.prepare_draft()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    assert has_element?(view, "span[aria-disabled='true']", "Import")
    refute has_element?(view, "span[phx-click='import']")
  end

  test "Import is live once the row is settled", %{conn: conn} do
    _settled = probed_item() |> settle()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    assert has_element?(view, "span[phx-click='import']", "Import")
    refute has_element?(view, "span[aria-disabled='true']")
  end

  # An imported item's draft is the record of what was imported; re-matching
  # would rebuild it. The row keeps a way into the record for looking, loses
  # the actions that write.
  test "an imported item's row offers no re-match", %{conn: conn} do
    item = probed_item() |> settle()
    {:ok, _media} = Ambry.Inbox.import_item(item)

    {:ok, view, _html} = live(conn, ~p"/admin/inbox?status=imported")

    refute has_element?(view, "span[phx-click='rescan'][phx-value-id='#{item.id}']")
    assert has_element?(view, "a[href^='/admin/inbox/#{item.id}']")
  end

  # Once it is imported, what the operator cares about is the audiobook, not
  # the release folder it arrived in. The matching details describe a decision
  # already taken and only make finished work read like work.
  test "an imported row is the audiobook it became", %{conn: conn} do
    item = probed_item() |> settle()
    {:ok, media} = Ambry.Inbox.import_item(item)

    {:ok, view, html} = live(conn, ~p"/admin/inbox?status=imported")

    # the library record, in the credit stack's words
    assert html =~ "The Way of Kings"
    assert html =~ "Brandon Sanderson"
    assert has_element?(view, "a[href='/admin/audiobooks/#{media.id}/edit']")

    # and none of the matching details, nor the files it came from
    refute html =~ item.path
    refute html =~ "reviewed"
    assert item_states(html) == []
  end

  # "Found" is when discovery tripped over the folder, which for a finished
  # row is the least interesting date it has. `updated_at` is stamped by the
  # status change and nothing writes to an imported item afterwards.
  test "an imported row is dated by the import, not the discovery", %{conn: conn} do
    item = probed_item() |> settle()
    {:ok, _media} = Ambry.Inbox.import_item(item)

    {:ok, _view, html} = live(conn, ~p"/admin/inbox?status=imported")

    assert html =~ "Imported #{Calendar.strftime(Inbox.get_item!(item.id).updated_at, "%x")}"
    refute html =~ "Found "
  end

  # Deleting an audiobook nilifies the link rather than taking the record of
  # the import with it, so the row outlives the thing it describes. It says
  # so, rather than falling back to matching details for a result that is
  # gone.
  test "an imported row whose audiobook was deleted says so", %{conn: conn} do
    item = probed_item() |> settle()
    {:ok, media} = Ambry.Inbox.import_item(item)
    {:ok, _deleted} = Ambry.Media.delete_media(media)

    {:ok, view, html} = live(conn, ~p"/admin/inbox?status=imported")

    assert html =~ "The audiobook this became has been deleted."
    refute has_element?(view, "a[href='/admin/audiobooks/#{media.id}/edit']")
    assert has_element?(view, "a[href^='/admin/inbox/#{item.id}']")
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

    assert html =~ "New candidates will show up here"
    assert_enqueued(worker: RunDiscovery)
  end

  test "ignores and restores without touching files", %{conn: conn} do
    item = probed_item()
    file = item |> Inbox.disk_files() |> hd()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='ignore'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "Files untouched"
    assert Inbox.get_item!(item.id).status == :ignored
    assert File.exists?(file)

    # the default view is pending, so the ignored item has left it
    refute has_element?(view, "span[phx-click='restore'][phx-value-id='#{item.id}']")

    {:ok, view, _html} = live(conn, ~p"/admin/inbox?status=ignored")

    view |> element("span[phx-click='restore'][phx-value-id='#{item.id}']") |> render_click()

    assert Inbox.get_item!(item.id).status == :pending
  end

  # Queued, not run here: importing re-probes every file and copies every
  # byte, and doing that inside the event blocked the whole queue page for the
  # length of a NAS copy.
  test "imports a settled item into the library, leaving files alone", %{conn: conn} do
    item = probed_item() |> settle()
    file = item |> Inbox.disk_files() |> hd()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    html =
      view |> element("span[phx-click='import'][phx-value-id='#{item.id}']") |> render_click()

    assert html =~ "Adding to the library"
    assert_enqueued(worker: RunImport, args: %{inbox_item_id: item.id})
    assert Inbox.get_item!(item.id).status == :pending

    # the fixture's own probe job shares this queue, so drain it all
    assert %{failure: 0, discard: 0} = Oban.drain_queue(queue: :media)

    assert %{status: :imported, media_id: media_id} = Inbox.get_item!(item.id)
    assert media_id
    assert File.exists?(file)
  end

  # A row handed to an import wears the same cover every other background job
  # gives it, and says which job it is — "Working on it" over a row you just
  # pressed Add on says nothing about whether the press landed.
  test "a row being imported says so and refuses clicks", %{conn: conn} do
    item = probed_item() |> settle()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")
    view |> element("span[phx-click='import'][phx-value-id='#{item.id}']") |> render_click()

    html = render(view)
    assert html =~ "Adding to the library…"
    assert has_element?(view, "[data-role='busy-overlay']")
  end

  # The queue can't say *what* is outstanding, so it doesn't offer a button
  # that would fail — it sends you to the form, which can.
  test "an unsettled item offers the form rather than an import button", %{conn: conn} do
    item = probed_item()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    refute has_element?(view, "span[phx-click='import'][phx-value-id='#{item.id}']")
    # the link carries the list state so every way back lands on this tab
    assert has_element?(view, "a[href^='/admin/inbox/#{item.id}']")
  end

  @tag :capture_log
  test "a refusal no curation can fix is visible before anything is clicked", %{conn: conn} do
    item = probed_item(unreadable: true)

    {:ok, view, html} = live(conn, ~p"/admin/inbox")

    assert html =~ "couldn&#39;t read the file"
    refute has_element?(view, "span[phx-click='import'][phx-value-id='#{item.id}']")
    assert Inbox.get_item!(item.id).status == :pending
  end

  # Readiness was a tab and is now a badge. Every draft gets opened either
  # way, so the bucket only ever split work that was going to be done in
  # full — and it cost every row a second badge to say which bucket it was
  # in. What varies from row to row is how much the row still owes.
  test "a row says what it still owes rather than which tab it is in", %{conn: conn} do
    ready = probed_item(name: "Settled") |> settle()
    {:ok, _outstanding} = probed_item(name: "Outstanding") |> Inbox.prepare_draft()

    {:ok, view, html} = live(conn, ~p"/admin/inbox")

    refute has_element?(view, "span[data-role='ready-filter']")

    states = item_states(html)
    assert "ready" in states
    assert Enum.any?(states, &(&1 =~ ~r/\d+ decisions? needed/))
    # the tab's own word, which never told two rows apart
    refute "pending" in states

    # the flag is still stored rather than recomputed per render — the
    # import button reads it, and `put_draft/2` is what keeps it honest
    assert Inbox.get_item!(ready.id).ready
  end

  # These were once mutually exclusive, so a settled item's action rail had
  # no way into its own form and the title link was the only road in.
  test "a settled row offers both Import and Open", %{conn: conn} do
    item = probed_item() |> settle()

    {:ok, view, _html} = live(conn, ~p"/admin/inbox")

    assert has_element?(view, "span[phx-click='import'][phx-value-id='#{item.id}']")
    assert has_element?(view, "a[href^='/admin/inbox/#{item.id}']")
  end

  test "filters by status", %{conn: conn} do
    keeper = probed_item(name: "Keeper")
    reject = probed_item(name: "Reject")
    {:ok, _item} = Inbox.ignore_item(reject)

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

  # The rows' badges, as text. Read out of the markup rather than asserted
  # against the raw HTML: the formatter puts the badge's content on its own
  # line, so an exact-string match on the rendered page is a whitespace bet.
  defp item_states(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='item-state']")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp probed_item(opts \\ []) do
    name = Keyword.get(opts, :name, "The Way of Kings [M4B]")
    files = Keyword.get(opts, :files, ["book.m4b"])

    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    release = Path.join(root, name)
    File.mkdir_p!(release)

    Enum.each(files, fn filename ->
      path = Path.join(release, filename)

      if Keyword.get(opts, :unreadable, false) do
        File.write!(path, "this is not audio")
      else
        fixture =
          if Path.extname(filename) == ".mp3", do: valid_audio(:mp3), else: tagged_fixture()

        File.cp!(fixture, path)
      end
    end)

    # A settled destination needs a root to place into. Root and fixtures
    # share a filesystem here, so the policy defaults to hardlinking, which
    # leaves the fixtures where the test put them.
    if Ambry.Library.list_roots() == [] do
      library = Ambry.Paths.source_media_disk_path("library-#{Ecto.UUID.generate()}")
      File.mkdir_p!(library)
      insert(:root, path: library)
    end

    watched =
      insert(:source, path: root, name: "Watched #{Ecto.UUID.generate()}")

    {:ok, _counts} = Inbox.discover(watched)

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
