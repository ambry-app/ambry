defmodule AmbryWeb.Admin.InboxLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  describe "the invariant" do
    test "an unsettled item can't be imported", %{conn: conn} do
      item = probed_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Still to settle"
      assert has_element?(view, "button[data-role='import'][disabled]")
    end

    test "a settled item can", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      refute html =~ "Still to settle"
      refute has_element?(view, "button[data-role='import'][disabled]")
    end

    test "importing creates the library records and returns to the queue", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view |> element("button[data-role='import']") |> render_click()

      assert %{status: :approved, media_id: media_id} = Inbox.get_item!(item.id)
      assert media_id
    end

    test "each outstanding decision is named, not just counted", %{conn: conn} do
      item = probed_item()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # tag-derived credits are never auto-settled, so the narrators from the
      # fixture's `composer` tag are listed by name
      assert html =~ "Michael Kramer"
      assert html =~ "needs confirming"
    end
  end

  describe "settling decisions" do
    test "take-the-top-suggestion settles everything that has one", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html = view |> element("button[phx-click='approve-all']") |> render_click()

      refute html =~ "Still to settle"
      assert Inbox.get_item!(item.id).ready
    end

    test "take-the-top-suggestion never invents a missing required value", %{conn: conn} do
      item = probed_item(dated: false)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")
      assert html =~ "First published"

      html = view |> element("button[phx-click='approve-all']") |> render_click()

      # the date nobody supplied is still outstanding — this button settles
      # choices, it does not fabricate facts
      assert html =~ "Still to settle"
      assert html =~ "First published"
      refute Inbox.get_item!(item.id).ready
    end

    test "typing a value records it as the operator's, and locks it", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> form("#work-form")
      |> render_change(%{
        "inbox_item" => %{
          "draft" => %{"work" => %{"title" => %{"value" => "A Title I Typed"}}}
        }
      })

      item = Inbox.get_item!(item.id)

      assert item.draft.work.title.value == "A Title I Typed"
      # 1d's lock semantics: editing a value is curation, so it records as the
      # operator's and a later refresh must not overwrite it
      assert item.draft.work.title.source == "manual"
      assert item.draft.work.title.approved
    end

    test "an accepted provider value records that provider, and stays unlocked", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element(
        "button[phx-click='choose-field'][phx-value-field='title'][phx-value-key='tags']"
      )
      |> render_click()

      item = Inbox.get_item!(item.id)

      assert item.draft.work.title.source == "tags"
      assert item.draft.work.title.approved
    end

    test "a credit can be dropped when the source proposed the wrong person", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      before = length(Inbox.get_item!(item.id).draft.recording.narrators)

      view
      |> element(
        "button[phx-click='remove-credit'][phx-value-section='recording'][phx-value-index='0']"
      )
      |> render_click()

      assert length(Inbox.get_item!(item.id).draft.recording.narrators) == before - 1
    end
  end

  describe "credits — credited as / written by" do
    test "the composite case is two people behind one credit", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      # the person layer is folded away for the ordinary case, so the pen-name
      # path starts by saying that this isn't one
      view
      |> element(
        "button[phx-click='toggle-people'][phx-value-section='work'][phx-value-index='0']"
      )
      |> render_click()

      html =
        view
        |> element(
          "button[phx-click='add-person'][phx-value-section='work'][phx-value-index='0']"
        )
        |> render_click()

      assert html =~ "A shared pen name"

      credit = hd(Inbox.get_item!(item.id).draft.work.authors)
      assert length(credit.people) == 2
    end

    test "naming both people creates one author and two people on import", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element(
        "button[phx-click='toggle-people'][phx-value-section='work'][phx-value-index='0']"
      )
      |> render_click()

      view
      |> element("button[phx-click='add-person'][phx-value-section='work'][phx-value-index='0']")
      |> render_click()

      {:ok, item} = Inbox.fetch_item(item.id)

      item =
        update_in(item.draft.work.authors, fn [credit | rest] ->
          [
            %{
              credit
              | name: "James S.A. Corey",
                people: [
                  %Draft.PersonRef{name: "Daniel Abraham"},
                  %Draft.PersonRef{name: "Ty Franck"}
                ]
            }
            | rest
          ]
        end)

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(item.draft))
      item = settle(item)

      assert {:ok, media} = Inbox.approve_item(item)

      book = media.book_id |> Ambry.Books.get_book!() |> Repo.preload(authors: :people)
      assert [author] = book.authors
      assert author.name == "James S.A. Corey"
      assert Enum.map(author.people, & &1.name) |> Enum.sort() == ["Daniel Abraham", "Ty Franck"]
    end

    test "an existing identity is linked rather than duplicated", %{conn: conn} do
      author = insert(:author, name: "Brandon Sanderson")
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#credit-work-0-identity")
      |> render_change(%{
        "section" => "work",
        "index" => "0",
        "identity_id" => to_string(author.id)
      })

      credit = hd(Inbox.get_item!(item.id).draft.work.authors)
      assert credit.mode == :link
      assert credit.identity_id == author.id
    end
  end

  describe "records are evidence, not identities" do
    test "the top record is ticked and the rest are not", %{conn: conn} do
      item = probed_item() |> with_work_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      assert view |> render() |> used_records() |> length() == 1
    end

    test "ticking a second record adds its values to the field chips", %{conn: conn} do
      item = probed_item() |> with_work_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("input[phx-click='toggle-source'][phx-value-id='hc-2']")
      |> render_click()

      work = Inbox.get_item!(item.id).draft.work

      assert length(work.sources) == 2
      # both databases now get a say, which is the whole point
      assert "Words of Radiance" in Enum.map(work.title.candidates, & &1.value)
    end

    test "an existing book is asked about separately from the records", %{conn: conn} do
      book = insert(:book, title: "The Way of Kings")
      item = probed_item() |> with_work_records(local: book)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Is this a book you already have?"

      view |> element("button[phx-click='link-book']") |> render_click()

      work = Inbox.get_item!(item.id).draft.work
      assert work.mode == :link
      assert work.book_id == book.id
    end

    test "the search that produced the records can be re-run", %{conn: conn} do
      item = probed_item() |> with_work_records()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Search again"
      assert has_element?(view, "form#research-work input[name='title']")
    end

    test "the file's own tags are visible", %{conn: conn} do
      item = probed_item()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "What the files say"
      assert html =~ "Michael Kramer"
    end
  end

  describe "fetching on demand" do
    # The `with` here had no `else`, so ticking a RECORDING record returned a
    # bare "recording" rather than {:ok, item} and the operator got an
    # instant "couldn't be reached" for a call that had actually succeeded.
    test "ticking a recording record does not report a failure", %{conn: conn} do
      item = probed_item() |> with_recording_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("input[phx-click='toggle-source'][phx-value-id='B01']")
        |> render_click()

      refute html =~ "couldn&#39;t be reached"
      assert render_async(view)

      assert Recording.uses?(Inbox.get_item!(item.id).draft.recording, %{
               "source" => "provider:audible",
               "id" => "B01"
             })
    end
  end

  describe "cover previews" do
    test "the file's own art is served rather than described in words", %{conn: conn} do
      item = probed_item(cover_art: true)

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # the embedded candidate's value is the audio file, not a URL, so it
      # needs an endpoint that extracts it — a line of text saying art exists
      # is the wrong answer for the one decision that is entirely visual
      assert html =~ "/admin/inbox/#{item.id}/embedded-cover"
    end

    test "the endpoint returns the extracted image", %{conn: conn} do
      item = probed_item(cover_art: true)

      conn = get(conn, ~p"/admin/inbox/#{item}/embedded-cover")

      assert response_content_type(conn, :jpg) =~ "image/jpeg"
      assert byte_size(response(conn, 200)) > 0
    end

    test "an item with no embedded art 404s rather than erroring", %{conn: conn} do
      item = probed_item()

      conn = get(conn, ~p"/admin/inbox/#{item}/embedded-cover")

      assert response(conn, 404)
    end
  end

  describe "background work" do
    # Matching now backs off for minutes rather than giving up on the first
    # rate limit, so an item can be legitimately mid-work while the form looks
    # like nothing was found. Those must not look the same.
    test "says when matching is still pending", %{conn: conn} do
      # discovery enqueues the probe and match jobs, so a fresh item has them
      item = probed_item()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Queued for matching"
    end

    test "says when a provider is being retried", %{conn: conn} do
      item = probed_item()
      retryable_jobs(item)

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # "waiting out a rate limit" and "queued" are the same blank form and
      # completely different situations
      assert html =~ "waiting to try again"
    end

    test "an item nothing is happening to says nothing about jobs", %{conn: conn} do
      item = probed_item() |> with_work_records()
      forget_jobs(item)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "[data-role='job-status']")
    end
  end

  describe "destination" do
    test "says where the file is going before anything is committed", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Referenced where it lies"
      assert html =~ "never move, rename or delete"
    end
  end

  # Two plausible works from one provider, so the record list is a real
  # question rather than a formality.
  defp with_work_records(item, opts \\ []) do
    candidate = fn id, title, published ->
      %{
        "source" => "provider:hardcover",
        "provider_name" => "Hardcover",
        "id" => id,
        "title" => title,
        "authors" => ["Brandon Sanderson"],
        "published" => published,
        "published_format" => "full",
        "score" => if(id == "hc-1", do: 0.95, else: 0.6)
      }
    end

    local =
      case Keyword.get(opts, :local) do
        nil -> []
        book -> [%{"id" => book.id, "title" => book.title, "score" => 0.8}]
      end

    {:ok, item} =
      item
      |> InboxItem.changeset(%{
        matches: %{
          "work" => %{
            "candidates" => [
              candidate.("hc-1", "The Way of Kings", "2010-08-31"),
              candidate.("hc-2", "Words of Radiance", "2014-03-04")
            ],
            "local" => local,
            "confidence" => 0.95,
            "query" => "The Way of Kings Brandon Sanderson",
            "query_fields" => %{
              "title" => "The Way of Kings",
              "author" => "Brandon Sanderson"
            }
          },
          "recording" => %{"candidates" => [], "confidence" => 0.0}
        }
      })
      |> Repo.update()

    {:ok, item} = Inbox.rebuild_draft(item)
    item
  end

  # The Oban pruner deletes jobs after a day, so absence of a job is the
  # normal state of an item that was matched last week.
  defp forget_jobs(item) do
    import Ecto.Query

    Repo.delete_all(
      from(j in "oban_jobs",
        where: fragment("?->>'inbox_item_id'", j.args) == ^to_string(item.id)
      )
    )
  end

  defp retryable_jobs(item) do
    import Ecto.Query

    Repo.update_all(
      from(j in "oban_jobs",
        where: fragment("?->>'inbox_item_id'", j.args) == ^to_string(item.id)
      ),
      set: [state: "retryable"]
    )
  end

  defp with_recording_records(item) do
    {:ok, item} =
      item
      |> InboxItem.changeset(%{
        matches: %{
          "work" => %{"candidates" => [], "local" => []},
          "recording" => %{
            "candidates" => [
              %{
                "source" => "provider:audible",
                "provider_name" => "Audible",
                "id" => "B01",
                "title" => "The Way of Kings",
                "narrators" => ["Michael Kramer", "Kate Reading"],
                "score" => 0.4,
                "hydrated" => true
              }
            ],
            "confidence" => 0.4
          }
        }
      })
      |> Repo.update()

    {:ok, item} = Inbox.rebuild_draft(item)
    item
  end

  defp used_records(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='record'][data-used='true']")
  end

  defp probed_item(opts \\ []) do
    name = Keyword.get(opts, :name, "The Way of Kings [M4B]")

    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    release = Path.join(root, name)
    File.mkdir_p!(release)

    File.cp!(
      tagged_fixture(Keyword.get(opts, :dated, true), Keyword.get(opts, :cover_art, false)),
      Path.join(release, "book.m4b")
    )

    {:ok, _counts} = Inbox.discover(root)
    {items, _more} = Inbox.list_items(filter: name)
    {:ok, item} = items |> hd() |> Inbox.probe_item()

    item
  end

  defp tagged_fixture(dated?, cover_art?) do
    dir = Ambry.Paths.source_media_disk_path("tagged-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "tagged.m4b")

    {_output, 0} =
      System.cmd(
        "ffmpeg",
        [
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
          "composer=Michael Kramer, Kate Reading"
        ] ++
          if(dated?, do: ["-metadata", "date=2010-08-31"], else: []) ++
          [path]
      )

    if cover_art?, do: attach_cover(path), else: path
  end

  # Cover art rides along as an attached_pic video stream. ffmpeg's mov muxer
  # is fussy about writing one, so the art goes into an mp3 — which the probe
  # and the extractor treat identically.
  defp attach_cover(path) do
    art = Path.rootname(path) <> ".jpg"
    with_art = Path.rootname(path) <> "-art.mp3"

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "quiet",
        "-y",
        "-f",
        "lavfi",
        "-i",
        "color=c=red:s=64x64:d=1",
        "-frames:v",
        "1",
        art
      ])

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "quiet",
        "-y",
        "-i",
        valid_audio(:mp3),
        "-i",
        art,
        "-map",
        "0:a",
        "-map",
        "1:v",
        "-c",
        "copy",
        "-id3v2_version",
        "3",
        "-metadata",
        "album=The Way of Kings",
        "-metadata",
        "artist=Brandon Sanderson",
        "-metadata",
        "composer=Michael Kramer, Kate Reading",
        "-metadata",
        "date=2010-08-31",
        with_art
      ])

    with_art
  end
end
