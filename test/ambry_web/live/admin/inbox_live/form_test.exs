defmodule AmbryWeb.Admin.InboxLive.FormTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.InboxItem
  alias Ambry.Metadata.PersonSearch
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

  describe "the escape hatch" do
    # Matching is keyword-based and good enough for the ordinary case, but a
    # file's idea of its title can be anything — the operator's own copy of
    # Philosopher's Stone is tagged "HP1 - The Philosopher's Stone", and the US
    # edition of the same work is called Sorcerer's Stone. No string comparison
    # should be asked to connect those, so there is always a way to go and look.
    test "the library can be searched by hand and linked", %{conn: conn} do
      book = insert(:book, title: "Harry Potter and the Sorcerer's Stone")
      item = probed_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # reachable from the default state, with nothing matched
      assert html =~ "search the library by title, author or series"

      html =
        view |> form("#library-search") |> render_change(%{"query" => "sorcerer stone"})

      assert html =~ "Harry Potter and the Sorcerer&#39;s Stone"

      view
      |> element("button[phx-click='link-book'][phx-value-id='#{book.id}']")
      |> render_click()

      draft = Inbox.get_item!(item.id).draft
      assert draft.work.mode == :link
      assert draft.work.book_id == book.id
    end

    test "says so when the library has nothing like it", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view |> form("#library-search") |> render_change(%{"query" => "nothing like this"})

      assert html =~ "Nothing in the library matches that"
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

    # Reachable from the DEFAULT state, not after unfolding: a self-narrated
    # import is the ordinary case, and a note explaining what is about to
    # happen is no use inside a control nobody would open.
    test "a self-narrated book says it will create one person", %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Same person as the author"

      # and the escape hatch is right there when two humans really do share a
      # name
      html =
        view
        |> element(
          ~s{button[phx-click='person-distinct'][phx-value-section='recording'][phx-value-distinct='true']}
        )
        |> render_click()

      assert html =~ "A different person who happens to share the name"
      assert [%{people: [person]}] = Inbox.get_item!(item.id).draft.recording.narrators
      assert person.distinct
    end

    # One human is one photo and one bio. Offering a second "find a photo" for
    # somebody already settled on the row above is the form contradicting
    # itself about what it is going to create.
    test "a shared person is curated in one place only", %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(
               view,
               ~s{button[phx-click='find-person-images'][phx-value-section='work'][phx-value-index='0']}
             )

      refute has_element?(
               view,
               ~s{button[phx-click='find-person-images'][phx-value-section='recording'][phx-value-index='0']}
             )

      assert render(view) =~ "Photo and bio come from the author credit"
    end

    # They are the same person, so they cannot hold different photos — the two
    # rows used to merge only at approval, which let the form show a state that
    # could never exist.
    test "a photo found on one credit lands on both rows", %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      send(
        view.pid,
        {:person_image_picked, %{section: "work", index: 0, person: 0},
         "https://example.test/face.jpg", "provider:tmdb"}
      )

      render(view)
      draft = Inbox.get_item!(item.id).draft

      assert [%{people: [author]}] = draft.work.authors
      assert [%{people: [narrator]}] = draft.recording.narrators
      assert author.image_url == "https://example.test/face.jpg"
      assert narrator.image_url == "https://example.test/face.jpg"
    end

    # Marking them distinct is the one edit that must NOT propagate: mirroring
    # it would mark both distinct and leave them indistinguishable, merging
    # them straight back together.
    test "saying they are different people gives the narrator its own controls",
         %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element(
        ~s{button[phx-click='person-distinct'][phx-value-section='recording'][phx-value-distinct='true']}
      )
      |> render_click()

      assert has_element?(
               view,
               ~s{button[phx-click='find-person-images'][phx-value-section='recording'][phx-value-index='0']}
             )

      draft = Inbox.get_item!(item.id).draft
      assert [%{people: [author]}] = draft.work.authors
      assert [%{people: [narrator]}] = draft.recording.narrators
      refute author.distinct
      assert narrator.distinct
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

  describe "person photos and bios" do
    # The offer has to be visible WITHOUT unfolding the pen-name control.
    # Nested inside it, it was hidden behind a link nobody would click to get
    # a picture — present in the markup and absent in practice.
    test "a new credit offers to go find a photo without unfolding anything", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "button[phx-click='toggle-people'][disabled]")

      assert has_element?(
               view,
               "button[phx-click='find-person-images'][phx-value-section='work'][phx-value-index='0']"
             )

      # and the narrator credits get their own, since they create people too
      assert has_element?(
               view,
               "button[phx-click='find-person-images'][phx-value-section='recording']"
             )
    end

    test "each person behind a pen name gets their own photo", %{conn: conn} do
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

      assert view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("[data-role='person-face']")
             |> length() >= 2
    end

    test "a picked photo is staged on the person", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      send(
        view.pid,
        {:person_image_picked, %{section: "work", index: 0, person: 0},
         "https://example.test/face.jpg", "provider:tmdb"}
      )

      render(view)

      assert [%{people: [person]}] = Inbox.get_item!(item.id).draft.work.authors
      assert person.image_url == "https://example.test/face.jpg"
      assert person.image_source == "provider:tmdb"
    end

    # A photo is picked by looking and a bio by reading. Sharing one modal meant
    # each dismissed the other, and a button labelled "find a photo and bio"
    # showed no bios at all until it closed. Both land on the row instead.
    test "photos and bios land on the credit row, with no modal", %{conn: conn} do
      patch_person_search()
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element(
        ~s{button[phx-click='find-person-images'][phx-value-section='work'][phx-value-index='0']}
      )
      |> render_click()

      html = render_async(view)

      # nothing opened, and BOTH halves of what the button promised are here
      refute html =~ "A photo for"
      assert html =~ "An American author of epic fantasy."
      assert has_element?(view, ~s{button[phx-click='pick-person-image']})

      view
      |> element(
        ~s{button[phx-click='pick-person-bio'][phx-value-section='work'][phx-value-bio='Q1']}
      )
      |> render_click()

      assert [%{people: [person]}] = Inbox.get_item!(item.id).draft.work.authors
      assert person.description == "An American author of epic fantasy."
      assert person.description_source == "provider:wikidata"
    end

    # A person's description is a description like any other: the recording's
    # has been an editable box since the form existed, and a provider's blurb
    # about a human is a starting point too.
    test "a bio can be typed over, and records as the operator's", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> form("#person-bio-work-0-0")
      |> render_change(%{
        "section" => "work",
        "index" => "0",
        "person" => "0",
        "description" => "Sanderson writes very fast."
      })

      assert [%{people: [person]}] = Inbox.get_item!(item.id).draft.work.authors
      assert person.description == "Sanderson writes very fast."
      assert person.description_source == "manual"
    end

    # A photo-heavy provider would otherwise push the rest of the credit off
    # screen; the point is that alternatives exist, not that all of them show.
    test "a large photo set folds away behind an expander", %{conn: conn} do
      patch_person_search(images: Enum.map(1..9, &"https://example.test/#{&1}.jpg"))
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element(
        ~s{button[phx-click='find-person-images'][phx-value-section='work'][phx-value-index='0']}
      )
      |> render_click()

      render_async(view)

      assert shown_photos(view) == 5
      assert has_element?(view, ~s{button[phx-click='toggle-photos']}, "show all 9 photos")

      view |> element(~s{button[phx-click='toggle-photos']}) |> render_click()

      assert shown_photos(view) == 9
    end

    defp shown_photos(view) do
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("button[phx-click='pick-person-image']")
      |> length()
    end

    defp patch_person_search(opts \\ []) do
      images = Keyword.get(opts, :images, ["https://example.test/face.jpg"])

      patch(PersonSearch, :providers, fn ->
        [%{id: "wikidata", display_name: "Wikidata"}]
      end)

      patch(PersonSearch, :matches, fn _provider, _query ->
        [
          %PersonSearch.Match{
            provider_id: "wikidata",
            provider_name: "Wikidata",
            id: "Q1",
            name: "Brandon Sanderson",
            description: "An American author of epic fantasy.",
            images: images
          }
        ]
      end)
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
      tagged_fixture(
        Keyword.get(opts, :dated, true),
        Keyword.get(opts, :cover_art, false),
        Keyword.get(opts, :narrator)
      ),
      Path.join(release, "book.m4b")
    )

    {:ok, _counts} = Inbox.discover(root)
    {items, _more} = Inbox.list_items(filter: name)
    {:ok, item} = items |> hd() |> Inbox.probe_item()

    item
  end

  defp tagged_fixture(dated?, cover_art?, narrator) do
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
          "composer=#{narrator || "Michael Kramer, Kate Reading"}"
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
