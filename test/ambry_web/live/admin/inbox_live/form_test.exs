defmodule AmbryWeb.Admin.InboxLive.FormTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.RunImport
  alias Ambry.Metadata.PersonSearch
  alias Ambry.Metadata.Providers
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

    # The import is queued and the operator is handed back to the queue at
    # once. It used to run in an async task owned by this LiveView, which
    # pinned them to a spinner and — the real defect — died with the process,
    # so closing the tab killed a copy mid-flight.
    test "importing queues a job and returns to the queue", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view |> element("button[data-role='import']") |> render_click()

      assert_redirect(view, ~p"/admin/inbox")
      assert_enqueued(worker: RunImport, args: %{inbox_item_id: item.id})

      # nothing has touched the library yet — that is the job's to do
      assert %{status: :pending, media_id: nil} = Inbox.get_item!(item.id)

      assert %{success: 1} = Oban.drain_queue(queue: :media)
      assert %{status: :imported, media_id: media_id} = Inbox.get_item!(item.id)
      assert media_id
    end

    # Returning them to an unfiltered page one is how "where did my queue go"
    # happens — they were on page three of Pending, and that is where they go
    # back. An unknown param is dropped rather than echoed, so a hand-typed
    # URL can't turn this into an open redirect.
    test "importing returns to the list the operator came from", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}?status=pending&page=3&junk=1")

      view |> element("button[data-role='import']") |> render_click()

      # params come back in map order, which is fine — it is the same list
      assert_redirect(view, ~p"/admin/inbox?page=3&status=pending")
    end

    test "returning keeps the issue the queue was narrowed to", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}?status=pending&problem=issue")

      view |> element("button[data-role='import']") |> render_click()

      # `problem` was missing from this form's whitelist, so importing out of a
      # queue narrowed to an issue dropped the operator back into the whole
      # queue.
      assert_redirect(view, ~p"/admin/inbox?problem=issue&status=pending")
    end

    # A stale tab can still send the event twice, and the second one must not
    # queue a second copy of a multi-gigabyte placement.
    test "a second import click doesn't queue a second job", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("button[data-role='import']") |> render_click()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("button[data-role='import']") |> render_click()

      assert [_only_one] = all_enqueued(worker: RunImport)
    end

    # The library moved between the draft being settled and Add being pressed,
    # which is the whole gap the pre-flight exists to cover. The order here is
    # the order it happens in: settle against a library that has nothing, then
    # something turns up.
    test "a book that arrived since the draft was settled stops the import", %{conn: conn} do
      item = probed_item() |> settle()
      have_way_of_kings()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      html = view |> element("button[data-role='import']") |> render_click()

      assert html =~ "Possible duplicates"
      assert html =~ "Book: The Way of Kings"
      assert has_element?(view, "[data-role='collisions']")
      assert has_element?(view, "button[data-role='import']", "Add it anyway")

      # nothing queued, nothing created, and the operator is still on the form
      refute_enqueued(worker: RunImport)
      assert %{status: :pending} = Inbox.get_item!(item.id)
    end

    test "pressing Add again is the answer, and it goes through", %{conn: conn} do
      item = probed_item() |> settle()
      have_way_of_kings()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("button[data-role='import']") |> render_click()
      view |> element("button[data-role='import']") |> render_click()

      assert_redirect(view, ~p"/admin/inbox")
      assert_enqueued(worker: RunImport, args: %{inbox_item_id: item.id})
    end

    # Editing anything changes what the import would create, so the answer
    # given about the old draft is not an answer about this one.
    test "changing the draft puts the question back", %{conn: conn} do
      item = probed_item() |> settle()
      have_way_of_kings()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("button[data-role='import']") |> render_click()

      html = render_click(view, "new-book", %{})

      refute html =~ "Possible duplicates"
      refute has_element?(view, "[data-role='collisions']")
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

  describe "an imported item" do
    # The draft is the record of what was imported — the library records were
    # created from it, so editing it afterwards makes the record lie. The
    # operator has done this by accident.
    test "reads as read-only: banner, no actions, inert sections", %{conn: conn} do
      item = probed_item() |> settle()
      {:ok, _media} = Inbox.import_item(item)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(view, "[data-role='imported-banner']")
      assert html =~ "In the library"
      refute has_element?(view, "button[data-role='import']")
      refute html =~ "Start over"
      assert has_element?(view, "#work[inert]")
      assert has_element?(view, "#recording[inert]")
      assert has_element?(view, "#destination[inert]")
    end

    test "refuses edits — markup is advisory, a stale tab can send anything", %{conn: conn} do
      item = probed_item() |> settle()
      {:ok, _media} = Inbox.import_item(item)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      before = Inbox.get_item!(item.id).draft

      html = render_click(view, "new-book", %{})

      assert Inbox.get_item!(item.id).draft == before
      assert html =~ "read-only"
    end

    # A failed attempt writes its reason onto the item so the row explains
    # itself tomorrow; succeeding is what resolves it. This one is from life:
    # an imported item sat with "Couldn't add this to the library" in red
    # while its media was in the library.
    test "importing clears the issue a failed attempt left behind" do
      item = probed_item() |> settle()
      {:ok, item} = Inbox.update_item(item, %{issue: "Couldn't add this to the library."})

      {:ok, _media} = Inbox.import_item(item)

      assert Inbox.get_item!(item.id).issue == nil
    end

    test "the context refuses a second import and any draft write" do
      item = probed_item() |> settle()
      {:ok, _media} = Inbox.import_item(item)
      item = Inbox.get_item!(item.id)

      assert {:error, :already_imported} = Inbox.import_item(item)
      assert {:error, :already_imported} = Inbox.update_draft(item, %{})
      assert {:error, :already_imported} = Inbox.rescan_item_async(item)
    end
  end

  describe "new or a replacement" do
    # The ordinary import must not grow a question it has to answer three
    # hundred times: nothing in the library claims these files, so the answer
    # is already given and the card is a search with nothing to do in it.
    test "an ordinary import answers it silently", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(view, "[data-role='replacement']")
      refute has_element?(view, "[data-role='local-recording']")
      refute html =~ "Whether this replaces an audiobook you already have"
      assert has_element?(view, "[data-role='import']", "Add to the library")
    end

    test "the path evidence proposes a recording, and blocks until answered", %{conn: conn} do
      item = probed_item()
      _media = library_recording(from: item)
      item = settle(item)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "This audiobook was imported from these files"
      assert has_element?(view, "[data-role='local-recording']", "The Way of Kings")
      # which recordings still cost double the disk is the reason somebody is
      # on this form, so the row says it
      assert has_element?(view, "[data-role='local-recording']", "streaming only")

      assert html =~ "Whether this replaces an audiobook you already have"
      assert has_element?(view, "button[data-role='import'][disabled]")
    end

    test "answering it collapses the rest of the form", %{conn: conn} do
      item = probed_item()
      _media = library_recording(from: item)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      # unsettled, so the book and audiobook sections are full of outstanding
      # decisions — and none of them are questions about a recording that
      # already exists
      assert has_element?(view, "#work")

      html = view |> element("[data-role='local-recording'] button") |> render_click()

      refute has_element?(view, "#work")
      refute has_element?(view, "#recording")
      refute has_element?(view, "#chapters")
      assert has_element?(view, "#destination")

      refute html =~ "Still to settle"
      assert has_element?(view, "[data-role='import']", "Replace the files")
    end

    # Green is one-way, but the way back to the machine's value never closes:
    # the declined proposal stays on the form.
    test "declining it keeps the row and puts the questions back", %{conn: conn} do
      item = probed_item()
      _media = library_recording(from: item)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("[data-role='local-recording'] button") |> render_click()
      view |> element("[data-role='new-recording']") |> render_click()

      assert has_element?(view, "#work")
      assert has_element?(view, "[data-role='local-recording']")
      assert has_element?(view, "[data-role='import']", "Add to the library")
    end

    test "any audiobook in the library is reachable by searching", %{conn: conn} do
      item = probed_item() |> settle()
      media = library_recording()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "[data-role='local-recording']")

      view
      |> element("#replace-recording-resolver-input")
      |> render_change(%{"resolver" => %{"replace-recording-resolver" => "Kings"}})

      view |> element("#replace-recording-resolver-option-#{media.id}") |> render_click()
      view |> form("#recording-search") |> render_change()

      assert %{mode: :replace, media_id: media_id} =
               Inbox.get_item!(item.id).draft.replacement

      assert media_id == media.id
    end

    test "nothing matching says so", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("#replace-recording-resolver-input")
        |> render_change(%{"resolver" => %{"replace-recording-resolver" => "Neuromancer"}})

      assert html =~ "No matches"
    end

    # The one consequence of a replacement that can't be taken back.
    test "warns that the existing files will be lost", %{conn: conn} do
      item = probed_item()
      _media = library_recording(from: item)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("[data-role='local-recording'] button") |> render_click()

      assert has_element?(view, "[data-role='replace-warning']")
    end

    # A hardlinked library copy shares its inode with the source it was placed
    # from. The bytes have another name, so removing this one destroys
    # nothing, and there is nothing to warn about.
    test "says nothing when the existing files are a known hardlink", %{conn: conn} do
      item = probed_item()
      _media = library_recording(from: item, hardlinked: true)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("[data-role='local-recording'] button") |> render_click()

      refute has_element?(view, "[data-role='replace-warning']")
    end

    # An answer can stop being true: nothing stops the audiobook being
    # deleted between the choice and the click, and the form may not offer a
    # button that fails.
    test "an audiobook deleted since it was chosen blocks the import", %{conn: conn} do
      item = probed_item() |> settle()
      media = library_recording()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#replace-recording-resolver-input")
      |> render_change(%{"resolver" => %{"replace-recording-resolver" => "Kings"}})

      view |> element("#replace-recording-resolver-option-#{media.id}") |> render_click()
      view |> form("#recording-search") |> render_change()

      {:ok, _deleted} = Ambry.Media.delete_media(Ambry.Media.get_media!(media.id))

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "has been deleted"
      assert has_element?(view, "button[data-role='import'][disabled]")
    end

    # An audiobook in the library as the reclaim finds them: no tracks,
    # streamed from a packaged artifact, with a real file behind it so the
    # link count means something.
    defp library_recording(opts \\ []) do
      workspace = Ambry.Paths.source_media_disk_path(Ecto.UUID.generate())
      File.mkdir_p!(workspace)
      served = Path.join(workspace, "book.m4b")
      File.write!(served, "served bytes")

      if opts[:hardlinked] do
        File.ln!(served, Path.join(workspace, "the-other-name.m4b"))
      end

      insert(:media,
        book: build(:book, title: "The Way of Kings"),
        source_path: Ambry.Paths.disk_to_web(workspace),
        source_files: [Ambry.Paths.disk_to_web(served)],
        mp4_path: Ambry.Paths.disk_to_web(served),
        legacy_source_files: legacy_source_files(opts[:from])
      )
    end

    defp legacy_source_files(nil), do: nil

    defp legacy_source_files(%InboxItem{} = item),
      do: item |> Repo.preload(:source) |> InboxItem.disk_files()
  end

  describe "settling decisions" do
    # The bulk "take the top suggestion" button is gone on purpose (operator:
    # they would rather settle each section with eyes on it than in bulk), so
    # what the outstanding list must do now is name the work and lead to it.
    test "what's outstanding is listed and links to its section", %{conn: conn} do
      item = probed_item(dated: false)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Still to settle"
      assert html =~ "First published"
      refute has_element?(view, "button[phx-click='approve-all']")
      assert has_element?(view, "[data-role='unresolved'] a[href='#work']")
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

      html =
        view
        |> element(
          "button[phx-click='remove-credit'][phx-value-section='recording'][phx-value-index='0']"
        )
        |> render_click()

      # a tombstone, not a deletion: the row stays, out of the decision
      # queue, rendered as a ghost the operator can take back
      assert [%{removed: true} | _rest] = Inbox.get_item!(item.id).draft.recording.narrators
      assert html =~ "data-role=\"removed-credit\""

      html =
        view
        |> element(
          "button[phx-click='restore-credit'][phx-value-section='recording'][phx-value-index='0']"
        )
        |> render_click()

      assert [%{removed: false} | _rest] = Inbox.get_item!(item.id).draft.recording.narrators
      refute html =~ "data-role=\"removed-credit\""
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

      view
      |> element("#library-book-resolver-input")
      |> render_change(%{"resolver" => %{"library-book-resolver" => "sorcerer stone"}})

      assert has_element?(view, "#library-book-resolver-option-#{book.id}")

      view |> element("#library-book-resolver-option-#{book.id}") |> render_click()
      view |> form("#library-search") |> render_change()

      draft = Inbox.get_item!(item.id).draft
      assert draft.work.mode == :link
      assert draft.work.book_id == book.id
    end

    # The keyword search the matched rows come from, not a substring of the
    # title: the author's name is what a person typing knows.
    test "a book is reachable by its author's name", %{conn: conn} do
      book =
        insert(:book,
          title: "The Way of Kings",
          book_authors: [build(:book_author, author: build(:author, name: "Brandon Sanderson"))]
        )

      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#library-book-resolver-input")
      |> render_change(%{"resolver" => %{"library-book-resolver" => "sanderson kings"}})

      assert has_element?(view, "#library-book-resolver-option-#{book.id}")
    end

    # The `fetch` half of a source, and it is load-bearing: there is no longer
    # a list of every book to find the linked one's name in, so a picker that
    # couldn't ask by id would render blank over a real answer.
    test "the box names the book it is holding, unsearched", %{conn: conn} do
      book = insert(:book, title: "Harry Potter and the Sorcerer's Stone")
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#library-book-resolver-input")
      |> render_change(%{"resolver" => %{"library-book-resolver" => "sorcerer"}})

      view |> element("#library-book-resolver-option-#{book.id}") |> render_click()
      view |> form("#library-search") |> render_change()

      # a fresh mount: nothing has been typed, and the box still says which
      # book this import is linked to
      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html
             |> Floki.parse_document!()
             |> Floki.find(~s{input[name="resolver[library-book-resolver]"]})
             |> Floki.attribute("value") == ["Harry Potter and the Sorcerer's Stone"]
    end

    test "says so when the library has nothing like it", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("#library-book-resolver-input")
        |> render_change(%{"resolver" => %{"library-book-resolver" => "nothing like this"}})

      assert html =~ "No matches"
    end
  end

  # The third level, and a section rather than a decoration on a credit. The
  # model always said people were a level — keyed decisions, `appearances/1` —
  # while the form rendered them inside every credit that named them.
  describe "the People section" do
    test "lists a human once, however many credits name them", %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      cards =
        html
        |> Floki.parse_document!()
        |> Floki.find("[data-role='person-card']")
        |> Enum.filter(&(Floki.text(&1) =~ "Brandon Sanderson"))

      assert [card] = cards
      assert Floki.text(card) =~ "Credited as author and narrator"
    end

    # A person exists because a credit names them, so the list is derived and
    # deliberately has no add of its own (design language §5).
    test "has no add of its own", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "#people button[phx-click='add-credit']")
      assert has_element?(view, "#people [data-role='person-card']")
    end

    # A full-cast recording is a run of credit rows; a second line of faces
    # each is what turns the section into a wall.
    test "a credit's people ride beside its box, and a crowd is counted", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      # the chips share the row with the identity box
      assert [chips] =
               view
               |> element("#work [data-role='credit-people']")
               |> render()
               |> Floki.parse_fragment!()

      assert Floki.find(chips, "a[href^='#person-']") != []

      # six humans behind one credit is a list, not a row of faces
      view
      |> element("#person-brandonsanderson button[phx-click='separate-name']")
      |> render_click()

      Enum.each(1..5, fn _ ->
        view
        |> element("#person-brandonsanderson button[phx-click='add-person']")
        |> render_click()
      end)

      assert [chips] =
               view
               |> element("#work [data-role='credit-people']")
               |> render()
               |> Floki.parse_fragment!()

      assert chips |> Floki.find("a[href^='#person-']") |> length() == 4
      assert chips |> Floki.find("a[href='#people']") |> Floki.text() =~ "+2"
    end

    # The credit keeps the identity decision and carries a reference, so the
    # operator can see who it means without leaving the section.
    test "a credit links to the person's card", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      key = hd(hd(Inbox.get_item!(item.id).draft.work.authors).person_keys)

      assert has_element?(view, "a[href='#person-#{key}']")
      assert has_element?(view, "#person-#{key}")
    end

    # A credit pointing at an identity the library already has brings no
    # humans with it: that person was chosen in the credit's typeahead and
    # carries curation an import may never overwrite.
    test "leaves out the people behind a linked credit", %{conn: conn} do
      item = probed_item()
      author = insert(:author, name: "Brandon Sanderson")

      {:ok, item} = Inbox.prepare_draft(item)
      draft = Draft.Edit.link_credit(item.draft, :work, 0, author.id)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      assert hd(Inbox.get_item!(item.id).draft.work.authors).mode == :link
      refute has_element?(view, "#person-brandonsanderson")
    end

    # The other direction is a decision made *here*, so it stays here. Losing
    # the card the moment the link was made took the way back with it, and
    # left the credit's chip pointing at an anchor that no longer existed.
    test "keeps a person matched to the library, with the way back", %{conn: conn} do
      item = probed_item()
      person = insert(:person, name: "Brandon Sanderson")

      {:ok, item} = Inbox.prepare_draft(item)
      key = hd(hd(item.draft.work.authors).person_keys)
      draft = Draft.Edit.link_person(item.draft, key, person.id)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(view, "#person-#{key}")

      view
      |> element("button[phx-click='unlink-person'][phx-value-key='#{key}']")
      |> render_click()

      assert %{mode: :create} = person_keyed(item, key)
    end
  end

  # The credited name is the human's name in almost every import, so the card
  # states it and offers nothing to type. "This is a pen name" is what puts a
  # box there — and with a box on every card in every state, the control had
  # no visible effect at all.
  describe "the person's name" do
    test "a card names the human and offers no box", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      card = view |> element("#person-brandonsanderson") |> render()

      assert card =~ "Brandon Sanderson"
      assert card =~ "Credited as author"
      # the reveal is the whole line: the title already says where the name
      # came from
      assert card =~ "This is a pen name"
      refute has_element?(view, "#person-brandonsanderson-resolver")
    end

    test "declaring a pen name is what puts a box there", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#person-brandonsanderson button[phx-click='separate-name']")
      |> render_click()

      assert has_element?(view, "#person-brandonsanderson-resolver")
      assert person_keyed(item, "brandonsanderson").own_name
    end

    # Both people controls live on the card they change. On the credit they
    # acted on a card the operator couldn't see, which is a change too far
    # away from the click.
    test "the credit carries no people controls", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "#work [phx-click='separate-name']")
      refute has_element?(view, "#work [phx-click='add-person']")
      assert has_element?(view, "#person-brandonsanderson [phx-click='separate-name']")
    end

    # The card is titled by the credit, which is the one name on it that
    # doesn't move: a header following the box re-titled the card letter by
    # letter while the operator typed the human's name into it.
    test "the card is titled by the credit, not by what is typed", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#person-brandonsanderson button[phx-click='separate-name']")
      |> render_click()

      view
      |> form("#person-brandonsanderson-identity")
      |> render_change(%{"key" => "brandonsanderson", "name" => "Somebody Else"})

      card = view |> element("#person-brandonsanderson") |> render()

      assert card =~ "Brandon Sanderson"
      assert card =~ "Credited as author"
      assert card =~ "A pen name of"
      assert card =~ "Somebody Else"
    end

    test "and it can be taken back", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#person-brandonsanderson button[phx-click='separate-name']")
      |> render_click()

      view
      |> element("button[phx-click='use-credited-name'][phx-value-key='brandonsanderson']")
      |> render_click()

      refute has_element?(view, "#person-brandonsanderson-resolver")
      refute person_keyed(item, "brandonsanderson").own_name
    end

    # A composite credit names nobody: "James S.A. Corey" is two humans, and
    # neither of them is called that.
    test "a credit standing for several humans always offers the box", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      add_second_person(view, "brandonsanderson")

      assert has_element?(view, "#person-brandonsanderson-resolver")
      # and the second human, whom the credit names no better than the first
      assert has_element?(view, "[data-role='pen-name-group'] #person-person\\#2")
    end

    # The author who turns up narrating: the credit's typeahead cannot offer
    # them, because the identity they need doesn't exist yet. Without a route
    # to the human the form's only answer was a second Person of the name.
    test "somebody the library already has is offered on the card", %{conn: conn} do
      person = insert(:person, name: "Brandon Sanderson")
      item = probed_item() |> with_local_person(person)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "already in your library"

      view
      |> element("button[phx-click='link-person'][phx-value-key='brandonsanderson']")
      |> render_click()

      assert %{mode: :link, person_id: id} = person_keyed(item, "brandonsanderson")
      assert id == person.id
    end

    # The operator's route: say the credit is a pen name, clear the box, type
    # a letter, pick the human out of the typeahead. The draft keeps the "j"
    # that was typed on the way — linking must not overwrite staged curation,
    # because unlinking has to give it back — but nothing should *render* it.
    test "a person linked through the typeahead reads as the library's own",
         %{conn: conn} do
      rowling = :person |> build(name: "J.K. Rowling") |> with_thumbnails() |> insert()
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#person-brandonsanderson button[phx-click='separate-name']")
      |> render_click()

      # typing narrows the typeahead, one keystroke at a time
      view
      |> element("#person-brandonsanderson-identity")
      |> render_change(%{"key" => "brandonsanderson", "name" => "j"})

      # and picking sends the id the resolver holds
      view
      |> element("#person-brandonsanderson-identity")
      |> render_change(%{
        "key" => "brandonsanderson",
        "name" => "j",
        "person_id" => to_string(rowling.id)
      })

      assert %{mode: :link, person_id: id} = person_keyed(item, "brandonsanderson")
      assert id == rowling.id

      chips =
        view
        |> element("#work [data-role='credit-people']")
        |> render()
        |> Floki.parse_fragment!()

      assert Floki.text(chips) =~ "J.K. Rowling"
      refute Floki.text(chips) |> String.trim() == "j"

      # her library portrait, not whichever candidate the half-typed name found
      assert Floki.find(chips, "img") |> Floki.attribute("src") ==
               [rowling.thumbnails.extra_small]
    end

    # Linking answers "who is this"; a pen name answers "whose name is on the
    # book". The second doesn't stop being true because the first was
    # answered from the library.
    test "a linked pen name still says whose pen name it is", %{conn: conn} do
      rowling = insert(:person, name: "J.K. Rowling")
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#person-brandonsanderson button[phx-click='separate-name']")
      |> render_click()

      view
      |> element("#person-brandonsanderson-identity")
      |> render_change(%{
        "key" => "brandonsanderson",
        "name" => "j",
        "person_id" => to_string(rowling.id)
      })

      card = view |> element("#person-brandonsanderson") |> render()

      assert card =~ "A pen name of"
      refute card =~ "This import will use the person you already have."
    end
  end

  describe "credits — credited as / written by" do
    test "the composite case is two people behind one credit", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      # No fold to open first: people are a section of their own, so "add
      # another person" is reachable from the credit directly.
      html = add_second_person(view, "brandonsanderson")

      # the two cards sit adjacent inside a bracket, which states the one
      # thing their own titles can't: that there are two of them behind the
      # single credited name
      assert html =~ "2 people behind this name"

      assert [_first, _second] =
               html
               |> Floki.parse_document!()
               |> Floki.find("[data-role='pen-name-group'] [data-role='person-card']")

      credit = hd(Inbox.get_item!(item.id).draft.work.authors)
      assert length(credit.person_keys) == 2
    end

    test "naming both people creates one author and two people on import", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      add_second_person(view, "brandonsanderson")

      {:ok, item} = Inbox.fetch_item(item.id)

      # name the credit, then each of the two humans behind it
      [first, second] = hd(item.draft.work.authors).person_keys

      draft =
        item.draft
        |> Draft.Edit.rename_credit(:work, 0, "James S.A. Corey")
        |> Draft.Edit.rename_person(first, "Daniel Abraham")
        |> Draft.Edit.rename_person(second, "Ty Franck")

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))
      item = settle(item)

      assert {:ok, media} = Inbox.import_item(item)

      book = media.book_id |> Ambry.Books.get_book!() |> Repo.preload(authors: :people)
      assert [author] = book.authors
      assert author.name == "James S.A. Corey"
      assert Enum.map(author.people, & &1.name) |> Enum.sort() == ["Daniel Abraham", "Ty Franck"]
    end

    # One human is one record, and now one *card*: they used to render inside
    # every credit that named them, so a self-narrated book showed the same
    # person twice with a sentence apologising for it.
    test "a self-narrated book creates one person, listed once", %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # one card, not one per credit, and it says it stands for both
      assert html =~ "Credited as author and narrator"

      assert [_only_one] =
               html
               |> Floki.parse_document!()
               |> Floki.find("[data-role='person-card']")
               |> Enum.filter(&(Floki.text(&1) =~ "Brandon Sanderson"))

      # and the escape hatch is on that one card, when two humans really do
      # share a name. It is addressed to the credit that introduced them —
      # the author, since that is where the person is listed.
      view
      |> element(
        ~s{button[phx-click='split-person'][phx-value-section='work'][phx-value-index='0']}
      )
      |> render_click()

      draft = Inbox.get_item!(item.id).draft
      assert [author] = hd(draft.work.authors).person_keys
      assert [narrator] = hd(draft.recording.narrators).person_keys
      assert author != narrator
    end

    # One human is one RECORD now, not two kept in step. Both credits point at
    # the same `PersonDecision`, so the photo shows in both places because it
    # is the same photo — there is no second copy to mirror onto.
    test "a self-narrated book stores exactly one person", %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, _view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      draft = Inbox.get_item!(item.id).draft

      assert length(draft.people) == 1
      assert hd(draft.work.authors).person_keys == hd(draft.recording.narrators).person_keys
    end

    # The edit that used to need mirroring. Setting the photo is now setting
    # the photo — there is nowhere else for it to be.
    test "a photo picked once is the photo everywhere", %{conn: conn} do
      item = probed_item(narrator: "Brandon Sanderson")

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      item = Inbox.get_item!(item.id)
      key = "brandonsanderson"

      draft = Draft.Edit.choose_person_bio(item.draft, key, "credit")
      {:ok, _saved} = Inbox.update_draft(item, Inbox.dump_draft(draft))
      render(view)

      draft = Inbox.get_item!(item.id).draft

      # one record, referenced from both credits — neither owns a copy, so
      # there is nothing to keep in step
      assert [person] = draft.people
      assert person.key == key
      assert hd(draft.work.authors).person_keys == [key]
      assert hd(draft.recording.narrators).person_keys == [key]
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

  describe "the entity resolver" do
    # One control for "attach to existing or create new": typing filters the
    # existing records — accent-blind, since "Rodriguez" must find
    # "Patricia Rodríguez" — while simultaneously offering to create what was
    # typed.
    test "typing offers matching records and a create row at once", %{conn: conn} do
      patricia = insert(:author, name: "Patricia Rodríguez")
      sanderson = insert(:author, name: "Brandon Sanderson")
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("#credit-work-0-resolver-input")
        |> render_change(%{"resolver" => %{"credit-work-0-resolver" => "rodrig"}})

      assert has_element?(view, "#credit-work-0-resolver-option-#{patricia.id}")
      refute has_element?(view, "#credit-work-0-resolver-option-#{sanderson.id}")
      assert html =~ "Create “rodrig”"
    end

    # Picking an option sets the hidden id; in the browser the value-change
    # hook then fires the surrounding form's change event, which the test
    # fires by hand the way the person-form tests always have.
    test "picking a record links it", %{conn: conn} do
      author = insert(:author, name: "Brandon Sanderson")
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#credit-work-0-resolver-input")
      |> render_change(%{"resolver" => %{"credit-work-0-resolver" => "sander"}})

      view |> element("#credit-work-0-resolver-option-#{author.id}") |> render_click()
      view |> form("#credit-work-0-identity") |> render_change()

      credit = hd(Inbox.get_item!(item.id).draft.work.authors)
      assert credit.mode == :link
      assert credit.identity_id == author.id
    end

    # What's typed IS the new record's name until something is picked — the
    # behaviour the old bare text input had, kept.
    test "typed text becomes the create-name", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#credit-work-0-resolver-input")
      |> render_change(%{"resolver" => %{"credit-work-0-resolver" => "Jason Pargin"}})

      view |> form("#credit-work-0-identity") |> render_change()

      credit = hd(Inbox.get_item!(item.id).draft.work.authors)
      assert credit.mode == :create
      assert credit.name == "Jason Pargin"
    end

    # The note beside a linked credit speaks only when the backing humans add
    # something the identity name doesn't — a pen name's real names. An
    # identity backed by a same-named person stays silent, and the lookup has
    # to work for identities picked at form time, not only seed-time matches.
    test "a linked pen name says who's behind it; a plain identity doesn't", %{conn: conn} do
      abraham =
        insert(:person,
          name: "Daniel Abraham",
          authors: [build(:author, name: "James S.A. Corey")]
        )

      [corey] = Ambry.Repo.preload(abraham, :authors).authors
      franck = insert(:person, name: "Ty Franck")
      {:ok, _} = Ambry.People.update_person(franck, %{author_people: [%{author_id: corey.id}]})

      solo = insert(:person, name: "Robin Sloan", authors: [build(:author, name: "Robin Sloan")])
      [sloan] = Ambry.Repo.preload(solo, :authors).authors

      item = probed_item()
      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      link = fn id ->
        view
        |> element("#credit-work-0-identity")
        |> render_change(%{"section" => "work", "index" => "0", "identity_id" => to_string(id)})
      end

      link.(corey.id)
      assert has_element?(view, "[data-role='identity-backing']", "Daniel Abraham and Ty Franck")

      link.(sloan.id)
      refute has_element?(view, "[data-role='identity-backing']")
    end

    # A filled field that opens must never list records that don't match what
    # it holds; and the suffix badge names the outcome the field currently
    # carries.
    test "an open filled field lists only what matches it", %{conn: conn} do
      sagan = insert(:author, name: "Carl Sagan")
      sanderson = insert(:author, name: "Brandon Sanderson")
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#credit-work-0-resolver-input")
      |> render_change(%{"resolver" => %{"credit-work-0-resolver" => "sagan"}})

      view |> element("#credit-work-0-resolver-option-#{sagan.id}") |> render_click()
      view |> form("#credit-work-0-identity") |> render_change()

      html = view |> element("#credit-work-0-resolver-input") |> render_focus()
      assert html =~ "existing"
      assert has_element?(view, "#credit-work-0-resolver-option-#{sagan.id}")
      refute has_element?(view, "#credit-work-0-resolver-option-#{sanderson.id}")
    end

    test "a series can be attached or created through the same control", %{conn: conn} do
      series = insert(:series, name: "The Expanse")
      item = probed_item()

      # stage a proposed membership the way matching would have
      {:ok, item} = Inbox.prepare_draft(item)
      params = Inbox.dump_draft(item.draft)

      params =
        put_in(params["work"]["series"], [
          %{"name" => "Expanse", "mode" => "create", "number" => "1", "source" => "tags"}
        ])

      {:ok, item} = Inbox.update_draft(item, params)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#series-0-resolver-input")
      |> render_change(%{"resolver" => %{"series-0-resolver" => "expanse"}})

      view |> element("#series-0-resolver-option-#{series.id}") |> render_click()
      view |> form("#series-0-link") |> render_change()

      link = hd(Inbox.get_item!(item.id).draft.work.series)
      assert link.mode == :link
      assert link.series_id == series.id
    end

    # A provider named the series and gave no number, so the row said
    # "nothing proposed it" beside "from rreading-glasses" — two sentences
    # about one row, contradicting each other. What is missing is the number.
    test "a numberless membership says the number is what it needs", %{conn: conn} do
      item = probed_item()

      {:ok, item} = Inbox.prepare_draft(item)
      params = Inbox.dump_draft(item.draft)

      params =
        put_in(params["work"]["series"], [
          %{"name" => "The Expanse", "mode" => "create", "source" => "provider:hardcover"}
        ])

      {:ok, item} = Inbox.update_draft(item, params)

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "needs a number"
      refute html =~ "nothing proposed it"
      # still a blocker — `book_number` is a required column
      assert html =~ "from Hardcover"
    end

    # The rail already says amber; a badge repeating it is the same fact
    # twice, which is the rule the rest of the form follows.
    test "a numbered membership awaiting confirmation wears no badge", %{conn: conn} do
      item = probed_item()

      {:ok, item} = Inbox.prepare_draft(item)
      params = Inbox.dump_draft(item.draft)

      params =
        put_in(params["work"]["series"], [
          %{"name" => "The Expanse", "mode" => "create", "number" => "1", "source" => "tags"}
        ])

      {:ok, item} = Inbox.update_draft(item, params)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      row = view |> element("[data-role='series-link']") |> render()

      refute row =~ "needs confirming"
      refute row =~ "nothing proposed it"
    end
  end

  describe "records are evidence, not identities" do
    # The person cards have worn the scrim since they grew a search of their
    # own; these two were left with a button that changed its own label.
    test "a level being searched wears the busy scrim", %{conn: conn} do
      test_pid = self()

      patch(Providers, :search_books, fn _id, _query, _opts ->
        send(test_pid, {:searching, self()})
        receive do: (:go -> :ok)
        {:ok, []}
      end)

      item = probed_item() |> with_work_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("form#research-work")
        |> render_submit(%{"level" => "work", "title" => "The Way of Kings"})

      assert_receive {:searching, task}
      assert html =~ "Looking for The Way of Kings…"

      send(task, :go)
      render_async(view)

      refute render(view) =~ "Looking for The Way of Kings…"
    end

    # The test above re-submits the title the item already had, so stored and
    # submitted agreed and the bug hid. Changing the value is the case: the
    # box and the scrim both described the PREVIOUS search until this one
    # landed — the typed words vanished from the box at the moment of the
    # click, and the scrim named the wrong book.
    test "a changed search is what the box and the scrim show, immediately",
         %{conn: conn} do
      test_pid = self()

      patch(Providers, :search_books, fn _id, _query, _opts ->
        send(test_pid, {:searching, self()})
        receive do: (:go -> :ok)
        {:ok, []}
      end)

      item = probed_item() |> with_work_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("form#research-work")
        |> render_submit(%{
          "level" => "work",
          "title" => "Oathbringer",
          "author" => "Sanderson"
        })

      assert_receive {:searching, task}

      assert html =~ "Looking for Oathbringer…"
      refute html =~ "Looking for The Way of Kings…"

      # and the words are still in the boxes that were typed into
      assert search_values(html, "#research-work") == %{
               "title" => "Oathbringer",
               "author" => "Sanderson"
             }

      send(task, :go)
      render_async(view)

      # the search landed: still what was asked for, now from storage
      assert search_values(render(view), "#research-work") == %{
               "title" => "Oathbringer",
               "author" => "Sanderson"
             }
    end

    # A recording matched by its ASIN stores `%{"keywords" => "B0…"}`, which
    # this form has no box for — so the audiobook card showed three empty
    # boxes above a Search button that submitted a blank query and, quite
    # correctly, did nothing whatsoever. A dead control that said nothing
    # about why.
    test "a level searched by ASIN still starts from something submittable",
         %{conn: conn} do
      item =
        probed_item()
        |> with_recording_records()
        |> then(fn item ->
          item
          |> InboxItem.changeset(%{
            matches:
              Map.update!(item.matches, "recording", fn level ->
                Map.put(level, "query_fields", %{"keywords" => "B08BKGYQXW"})
              end)
          })
          |> Repo.update!()
        end)

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # the boxes hold the hints matching itself searched with
      values = search_values(html, "#research-recording")
      assert values["title"] == "The Way of Kings"
      refute values["title"] == ""
    end

    # The recording level is the same form with a narrator box, and gets the
    # same rule — the point of fixing this once.
    test "the recording level's search behaves the same", %{conn: conn} do
      test_pid = self()

      patch(Providers, :search_books, fn _id, _query, _opts ->
        send(test_pid, {:searching, self()})
        receive do: (:go -> :ok)
        {:ok, []}
      end)

      item = probed_item() |> with_recording_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("form#research-recording")
        |> render_submit(%{
          "level" => "recording",
          "title" => "Oathbringer",
          "author" => "Sanderson",
          "narrator" => "Kate Reading"
        })

      assert_receive {:searching, task}

      assert html =~ "Looking for Oathbringer…"

      assert search_values(html, "#research-recording") == %{
               "title" => "Oathbringer",
               "author" => "Sanderson",
               "narrator" => "Kate Reading"
             }

      send(task, :go)
      render_async(view)
    end

    # Which database said this is the first thing an operator checks, and at
    # the end of the facts line it was the first thing truncation took.
    test "a record's provider is a badge, not the tail of a long line", %{conn: conn} do
      item = probed_item() |> with_work_records()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      row = html |> Floki.parse_document!() |> Floki.find("[data-role='record']") |> hd()

      # beside the title, not under it: `<.badge>` renders a div, and a div
      # inside a `<p>` closes the paragraph early and drops onto its own line
      assert [title_line] = Floki.find(row, "div.font-medium")
      assert [badge] = Floki.find(title_line, "[data-role='record-source']")
      assert Floki.text(badge) =~ "Hardcover"

      # and the facts line no longer carries it, so nothing repeats and
      # nothing about the source can be truncated away
      refute row |> Floki.find("p.truncate") |> Floki.text() =~ "Hardcover"
    end

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

      assert html =~ "Existing book?"

      view |> element("button[phx-click='link-book']") |> render_click()

      work = Inbox.get_item!(item.id).draft.work
      assert work.mode == :link
      assert work.book_id == book.id
    end

    # Eight rows all wearing the same weight is how a 6% study guide got read
    # as an alternative worth considering.
    test "a junk record is folded away behind a link", %{conn: conn} do
      item = probed_item() |> with_work_records(scores: %{"hc-2" => 0.12})

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Show 1 worse match"
      assert folded_records(html) == ["hc-2"]
    end

    test "nothing is folded when every record is worth showing", %{conn: conn} do
      item = probed_item() |> with_work_records()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      refute html =~ "worse match"
      assert folded_records(html) == []
    end

    # A low score is exactly why somebody would have gone looking for it by
    # hand; folding it away afterwards would show a decision with no cause.
    test "a ticked record is never folded, whatever it scores", %{conn: conn} do
      item = probed_item() |> with_work_records(scores: %{"hc-2" => 0.12})

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("input[phx-click='toggle-source'][phx-value-id='hc-2']")
        |> render_click()

      assert folded_records(html) == []
      assert html =~ "hc-2"
    end

    # Square art is the audiobook and a portrait is the print cover, and
    # cropping to fill made those two indistinguishable. The box is reserved
    # either way so the titles stay on one rail.
    test "a cover keeps its shape, and a record without one still reserves the space",
         %{conn: conn} do
      item =
        probed_item()
        |> with_work_records(covers: %{"hc-1" => "https://example.test/cover.jpg"})

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")
      rows = html |> Floki.parse_document!() |> Floki.find("[data-role='record']")

      assert [with_cover, without] = rows
      assert [class] = with_cover |> Floki.find("img") |> Floki.attribute("class")
      assert class =~ "object-contain"
      refute class =~ "object-cover"

      assert without |> Floki.find("[title='No image']") != []
      assert without |> Floki.find("img") == []
    end

    test "the search that produced the records can be re-run", %{conn: conn} do
      item = probed_item() |> with_work_records()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Search again"
      assert has_element?(view, "form#research-work input[name='title']")
    end

    # Not behind a disclosure: this is the evidence every decision below it
    # is an interpretation of.
    test "the file's own tags are visible without opening anything", %{conn: conn} do
      item = probed_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Embedded tags"
      assert html =~ "Michael Kramer"
      refute has_element?(view, "details [data-role='tags']")
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

      # the search-again form is the person level's re-search, same pattern
      # as the work and recording levels
      assert has_element?(view, "form[phx-submit='research-person']")
    end

    test "each person behind a pen name gets their own photo", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      add_second_person(view, "brandonsanderson")

      assert view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("[data-role='person-face']")
             |> length() >= 2
    end

    # Matching already asked every person provider, so the photos are on the
    # person's own field and the grid renders with nothing to click first.
    test "a photo matching found is already staged on the person", %{conn: conn} do
      item = probed_item(person_photo: "https://example.test/face.jpg")

      {:ok, _view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      person = person_keyed(item, "brandonsanderson")
      assert Field.value(person.image) == "https://example.test/face.jpg"
      assert person.image.source == "provider:wikidata"
    end

    # A photo is picked by looking and a bio by reading. Sharing one modal meant
    # each dismissed the other, and a button labelled "find a photo and bio"
    # showed no bios at all until it closed. Both land on the row instead.
    test "photos and bios land on the credit row, with no modal", %{conn: conn} do
      patch_person_search()
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("form#research-person-work-0-0")
      |> render_submit(%{"key" => "brandonsanderson", "name" => "Brandon Sanderson"})

      html = render_async(view)

      # nothing opened, and BOTH halves of what the button promised are here
      refute html =~ "A photo for"
      assert html =~ "An American author of epic fantasy."
      assert has_element?(view, ~s{button[phx-click='pick-person-image']})

      view |> element(~s{button[phx-click='pick-person-bio']}) |> render_click()

      person = person_keyed(item, "brandonsanderson")
      assert Field.value(person.description) == "An American author of epic fantasy."
      assert person.description.source == "provider:wikidata"
    end

    # The box holds the query, the way the work level's holds `query_fields`.
    # It rendered the person's name decision instead, so a search for anything
    # else worked and then snapped back the moment the results landed — at
    # the one moment the operator needs to see what produced them.
    test "the search box keeps the name that was searched for", %{conn: conn} do
      patch_person_search()
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("form#research-person-work-0-0")
      |> render_submit(%{"key" => "brandonsanderson", "name" => "Robert Galbraith"})

      render_async(view)

      assert view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("form#research-person-work-0-0 input[name='name']")
             |> Floki.attribute("value") == ["Robert Galbraith"]

      # and the person is still the person: a query is not a rename
      assert Field.value(person_keyed(item, "brandonsanderson").name) == "Brandon Sanderson"
    end

    # The same rule as the work and recording levels, and the same two
    # symptoms before it: the box fell back to the person's own name for the
    # length of the round trip, and the scrim over it named that person while
    # a search for somebody else was in flight.
    test "a person search shows the searched name while it runs, not the person's",
         %{conn: conn} do
      test_pid = self()

      patch(PersonSearch, :providers, fn -> [%{id: "wikidata", display_name: "Wikidata"}] end)

      patch(PersonSearch, :matches_with_outcome, fn _provider, _query, _opts ->
        send(test_pid, {:searching, self()})
        receive do: (:go -> :ok)
        {[], []}
      end)

      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("form#research-person-work-0-0")
        |> render_submit(%{"key" => "brandonsanderson", "name" => "Robert Galbraith"})

      assert_receive {:searching, task}

      assert html =~ "Looking for Robert Galbraith…"
      refute html =~ "Looking for Brandon Sanderson…"

      assert html
             |> Floki.parse_document!()
             |> Floki.find("form#research-person-work-0-0 input[name='name']")
             |> Floki.attribute("value") == ["Robert Galbraith"]

      send(task, :go)
      render_async(view)
    end

    # A person the matcher doubted is seeded unapproved, and until this the
    # only control in the whole form that could approve one was linking them
    # to somebody already in the library — 96 of the operator's 344 queued
    # items held a person no control could settle.
    test "a doubted person can be settled by none of these", %{conn: conn} do
      # the matcher found humans of roughly this name and believed none of
      # them, which is what seeds a person unapproved
      item = probed_item() |> with_namesake_person_matches()

      {:ok, item} = Inbox.prepare_draft(item)
      person = person_keyed(item, "brandonsanderson")

      refute person.approved
      assert person.doubt == :low_confidence
      assert Enum.any?(Draft.unresolved(item.draft), &(&1.label =~ "Brandon Sanderson"))

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("#person-brandonsanderson button[data-role='none-of-these']")
      |> render_click()

      person = person_keyed(item, "brandonsanderson")
      assert person.approved
      assert person.sources == []
      assert person.doubt == :none

      refute Enum.any?(
               Draft.unresolved(Inbox.get_item!(item.id).draft),
               &(&1.label =~ "Brandon Sanderson" and &1.section == :people)
             )
    end

    # The person level's records are evidence with checkboxes, the same rule
    # as the work and recording levels. Unticking the only record of a
    # namesake — the goalkeeper who shares a narrator's name — takes his face
    # and bio out of the pools instead of leaving them as the leading
    # suggestions.
    test "unticking a person record takes its face out of the pools", %{conn: conn} do
      item = probed_item(person_photo: "https://example.test/face.jpg")

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("input[phx-click='toggle-person-source'][phx-value-key='brandonsanderson']")
      |> render_click()

      person = person_keyed(item, "brandonsanderson")
      assert person.sources == []
      assert person.image.candidates == []
      assert Field.value(person.image) == nil

      # and the tick survives a rebuild of the rest of the draft
      assert person.evidence_curated
    end

    # A provider round-trip is the same kind of event as a matching job and
    # gets the same answer. The only sign it was happening used to be a button
    # changing its own label, inside a fold that closed over it on the very
    # patch that started the work.
    test "a person being looked up wears the busy scrim", %{conn: conn} do
      test_pid = self()
      patch(PersonSearch, :providers, fn -> [%{id: "wikidata", display_name: "Wikidata"}] end)

      patch(PersonSearch, :matches_with_outcome, fn _provider, _query, _opts ->
        send(test_pid, {:searching, self()})
        receive do: (:go -> :ok)
        {[], [%{"id" => "wikidata", "name" => "Wikidata", "status" => "ok", "count" => 0}]}
      end)

      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html =
        view
        |> element("form#research-person-work-0-0")
        |> render_submit(%{"key" => "brandonsanderson", "name" => "Jason Pargin"})

      assert_receive {:searching, task}
      assert html =~ "Looking for"
      assert has_element?(view, "#person-brandonsanderson [data-role='busy-overlay']")

      send(task, :go)
      render_async(view)

      refute has_element?(view, "#person-brandonsanderson [data-role='busy-overlay']")
    end

    # A card of search results is a search form with results below it. The
    # search used to be folded away *under* the results it produced, where the
    # patch carrying its own progress could close it.
    test "the search sits above the results, unfolded", %{conn: conn} do
      patch_person_search()
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      card =
        view |> element("#person-brandonsanderson") |> render() |> Floki.parse_fragment!()

      assert Floki.find(card, "form#research-person-work-0-0") != []
      # not behind a fold of its own
      assert card |> Floki.find("details") |> Floki.raw_html() =~ "worse match" or
               Floki.find(card, "details") == []
    end

    # The reported flow: looking up David Wong, then Jason Pargin, and getting
    # one list where both are perfect answers. Evidence is never deleted, so
    # what has to happen is that it stops competing.
    test "records the old name found sink out of the way", %{conn: conn} do
      patch(PersonSearch, :providers, fn -> [%{id: "wikidata", display_name: "Wikidata"}] end)

      patch(PersonSearch, :matches_with_outcome, fn _provider, _query, _opts ->
        {[
           %PersonSearch.Match{
             provider_id: "wikidata",
             provider_name: "Wikidata",
             id: "Q2",
             name: "Jason Pargin",
             description: "Writes comic horror.",
             images: []
           }
         ], [%{"id" => "wikidata", "name" => "Wikidata", "status" => "ok", "count" => 1}]}
      end)

      item = probed_item(person_photo: "https://example.test/face.jpg")

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")
      refute html =~ "worse match"

      # the operator's flow: say the credited name is a pen name, name the
      # human, then go looking for who they now are
      view
      |> element("#person-brandonsanderson button[phx-click='separate-name']")
      |> render_click()

      view
      |> form("#person-brandonsanderson-identity")
      |> render_change(%{"key" => "brandonsanderson", "name" => "Jason Pargin"})

      view
      |> element("form#research-person-work-0-0")
      |> render_submit(%{"key" => "brandonsanderson", "name" => "Jason Pargin"})

      html = render_async(view)

      # both are still there — a photo already picked from the old one must
      # not vanish — but only the human being asked about is in the running
      assert html =~ "Jason Pargin"
      assert html =~ "Show 1 worse match"

      assert [%{"name" => "Jason Pargin"}, %{"name" => "Brandon Sanderson", "score" => +0.0}] =
               Inbox.get_item!(item.id).matches["people"]["brandonsanderson"]["candidates"]
    end

    # A person's description is a description like any other: the recording's
    # has been an editable box since the form existed, and a provider's blurb
    # about a human is a starting point too.
    test "a bio can be typed over, and records as the operator's", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      key = "brandonsanderson"

      view
      |> form("#person-bio-work-0-0")
      |> render_change(%{"key" => key, "description" => "Sanderson writes very fast."})

      person = person_keyed(item, "brandonsanderson")
      assert Field.value(person.description) == "Sanderson writes very fast."
      assert person.description.source == "manual"
    end

    # A photo-heavy provider would otherwise push the rest of the credit off
    # screen; the point is that alternatives exist, not that all of them show.
    test "a large photo set folds away behind an expander", %{conn: conn} do
      patch_person_search(images: Enum.map(1..9, &"https://example.test/#{&1}.jpg"))
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("form#research-person-work-0-0")
      |> render_submit(%{"key" => "brandonsanderson", "name" => "Brandon Sanderson"})

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

      patch(PersonSearch, :matches_with_outcome, fn _provider, _query, _opts ->
        {[
           %PersonSearch.Match{
             provider_id: "wikidata",
             provider_name: "Wikidata",
             id: "Q1",
             name: "Brandon Sanderson",
             description: "An American author of epic fantasy.",
             images: images
           }
         ], [%{"id" => "wikidata", "name" => "Wikidata", "status" => "ok", "count" => 1}]}
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
      item = probed_item(busy: true)

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Queued for matching"
    end

    test "says when a provider is being retried", %{conn: conn} do
      item = probed_item(busy: true)
      retryable_jobs(item)

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # "waiting out a rate limit" and "queued" are the same blank form and
      # completely different situations
      assert html =~ "Retrying…"
    end

    # Matching keeps retrying until every provider has answered, and rebuilds
    # an untouched draft when one finally comes back — so a form with a job on
    # it is not the operator's to edit, and an edit accepted here would be
    # thrown away by work they couldn't see.
    test "a form with a job on it is covered and cannot be edited", %{conn: conn} do
      item = probed_item(busy: true)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # said over the whole form, not in a badge in the corner
      assert has_element?(view, "[data-role='busy-overlay']")
      assert html =~ "Queued for matching"
      assert html =~ "inert"
    end

    # `inert` and a scrim are markup, and markup is advisory: a stale tab or a
    # reconnect can still send an event. The refusal is the enforcement.
    test "events are refused while a job owns the item", %{conn: conn} do
      item = probed_item(busy: true) |> with_work_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      before = Inbox.get_item!(item.id).draft

      render_click(view, "waive-field", %{"section" => "work", "field" => "published"})

      render_click(view, "approve-credit", %{
        "section" => "work",
        "index" => "0",
        "approved" => "true"
      })

      assert Inbox.get_item!(item.id).draft == before
    end

    test "the cover comes off once nothing is working on it", %{conn: conn} do
      item = probed_item(busy: true) |> with_work_records()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      assert has_element?(view, "[data-role='busy-overlay']")

      # the job finishes; the form polls and lets go
      forget_jobs(item)
      send(view.pid, :refresh_job)

      render(view)

      refute has_element?(view, "[data-role='busy-overlay']")
    end

    test "an item nothing is happening to says nothing about jobs", %{conn: conn} do
      item = probed_item() |> with_work_records()
      forget_jobs(item)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "[data-role='job-status']")
    end
  end

  describe "part-of-a-set membership" do
    # A set membership is a decision like a series membership, reachable from
    # the form's default state: declare the set, name it, number the part.
    test "declaring, numbering and naming a new set from the default state", %{conn: conn} do
      item = probed_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")
      assert html =~ "Part of a set"
      assert html =~ "Not part of a set."

      view |> element("button", "This audiobook is part of a set") |> render_click()

      assert has_element?(view, "[data-role='group-link']")

      view
      |> form("#group-part")
      |> render_change(%{"part_number" => "1"})

      view
      |> form("#group-total")
      |> render_change(%{"parts_total" => "2"})

      # nothing to join, so the row is a name box and nothing else
      refute has_element?(view, "#group-dropdown")
      assert has_element?(view, "[data-role='group-name']")

      view
      |> form("#group-link")
      |> render_change(%{"name" => "GraphicAudio"})

      item = Inbox.get_item!(item.id)
      link = item.draft.recording.recording_group

      assert %{
               mode: :create,
               name: "GraphicAudio",
               part_number: 1,
               parts_total: 2,
               curated: true
             } = link
    end

    test "an operator-added link really deletes; a confirm approves", %{conn: conn} do
      item = probed_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view |> element("button", "This audiobook is part of a set") |> render_click()

      view
      |> form("#group-part")
      |> render_change(%{"part_number" => "1"})

      view
      |> form("#group-link")
      |> render_change(%{"name" => "GraphicAudio"})

      # the Confirm button appears once a part number exists
      view |> element("[data-role='group-link'] button", "Confirm") |> render_click()

      item = Inbox.get_item!(item.id)
      assert item.draft.recording.recording_group.approved

      # removing a manual link deletes it outright — nothing proposed it
      view
      |> element("[data-role='group-link'] button[phx-click='remove-group']")
      |> render_click()

      item = Inbox.get_item!(item.id)
      assert item.draft.recording.recording_group == nil
      assert has_element?(view, "button", "This audiobook is part of a set")
    end
  end

  describe "joining a set that already exists" do
    # The whole reason the control is two controls. Whether there is a set to
    # join is knowable — the draft carries the book's sets as candidates — so
    # the form says so, rather than making the operator discover it by typing
    # into a search box whose answer, for a book not in the library yet, is
    # always "no matches".
    test "the drop-down lists the book's sets and a way to make a new one", %{conn: conn} do
      %{item: item} = item_with_candidate_set()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      html = view |> element("#group-dropdown-trigger") |> render_click()

      assert html =~ "GraphicAudio"
      assert html =~ "New set"
    end

    # The drop-down's own click cannot be driven from here: it answers
    # server-side and the form only learns the answer when the
    # `entity-resolver-input` hook fires an `input` event, which no LiveView
    # test runs. So these post what that hook posts. The bridge itself is the
    # resolver's, shared and long-standing.
    test "choosing one links it", %{conn: conn} do
      %{item: item, group: group} = item_with_candidate_set()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> form("#group-link")
      |> render_change(%{"recording_group_id" => to_string(group.id)})

      link = Inbox.get_item!(item.id).draft.recording.recording_group
      group_id = group.id

      assert %{mode: :link, recording_group_id: ^group_id, curated: true} = link
    end

    test "choosing New set goes back to creating one, keeping the name", %{conn: conn} do
      %{item: item, group: group} = item_with_candidate_set()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> form("#group-link")
      |> render_change(%{"recording_group_id" => to_string(group.id)})

      # switching back posts no name — the box is not on the page while a set
      # is linked — and the set's name is not something to throw away because
      # a drop-down moved
      view |> form("#group-link") |> render_change(%{"recording_group_id" => "new"})

      link = Inbox.get_item!(item.id).draft.recording.recording_group

      assert link.mode == :create
      assert link.name == "GraphicAudio"
    end

    test "the name box is only there when a set is being made", %{conn: conn} do
      %{item: item, group: group} = item_with_candidate_set()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(view, "[data-role='group-name']")

      view
      |> form("#group-link")
      |> render_change(%{"recording_group_id" => to_string(group.id)})

      refute has_element?(view, "[data-role='group-name']")
    end
  end

  describe "splitting a mis-grouped item" do
    # The folder heuristic's known failure: two separate single-file books in
    # one folder become one 2-file item. The correction has to be reachable
    # from the form's default state.
    test "the split button breaks the item into one per file", %{conn: conn} do
      root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
      release = Path.join(root, "Two Novellas")
      File.mkdir_p!(release)
      File.cp!(tagged_fixture(true, false, nil), Path.join(release, "one.m4b"))
      File.cp!(tagged_fixture(true, false, nil), Path.join(release, "two.m4b"))

      {:ok, _counts} = discover(root)
      {[item], _more} = Inbox.list_items(filter: "Two Novellas")
      {:ok, item} = Inbox.probe_item(item)
      Repo.delete_all(Oban.Job)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # Two files are one recording by default — the buttons are the way to
      # say they aren't, not a precondition for importing them.
      assert html =~ "Not one audiobook?"
      assert html =~ "Split into 2 files"
      # one folder, so there is nothing for the coarser grain to divide
      refute has_element?(view, "button[data-role='split-folder']")

      view |> element("button[data-role='split']") |> render_click()
      assert_redirect(view, ~p"/admin/inbox")

      {items, _more} = Inbox.list_items(filter: "Two Novellas")
      assert length(items) == 2
      assert Enum.all?(items, &(length(&1.files) == 1))
    end

    # The other grain the heuristic gets wrong, and the reason this exists: a
    # folder of "1 of 5" subfolders is one release in five parts when it is a
    # multi-disc rip, and five recordings when it is a GraphicAudio set. Only
    # the operator can tell, and one item per *file* was no use to them —
    # each part is seven files.
    test "a set of part folders splits by folder, keeping each part whole", %{conn: conn} do
      root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
      release = Path.join(root, "The Way of Kings")

      for part <- 1..3, file <- 1..2 do
        dir = Path.join(release, "#{part} of 3")
        File.mkdir_p!(dir)
        File.cp!(tagged_fixture(true, false, nil), Path.join(dir, "part#{file}.m4b"))
      end

      {:ok, _counts} = discover(root)
      {[item], _more} = Inbox.list_items(filter: "The Way of Kings")
      {:ok, item} = Inbox.probe_item(item)
      Repo.delete_all(Oban.Job)

      # discovery reads the part folders as one release, which is the whole
      # bug from the operator's side
      assert length(item.files) == 6

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")
      assert html =~ "Split into 3 folders"

      view |> element("button[data-role='split-folder']") |> render_click()
      assert_redirect(view, ~p"/admin/inbox")

      {items, _more} = Inbox.list_items(filter: "The Way of Kings")
      assert length(items) == 3
      assert Enum.all?(items, &(length(&1.files) == 2))

      # and each says what it is a part of, since "1 of 3" alone names nothing
      assert Enum.map(items, &InboxItem.name/1) |> Enum.sort() ==
               ["The Way of Kings/1 of 3", "The Way of Kings/2 of 3", "The Way of Kings/3 of 3"]

      # a rescan must not re-merge what the operator just took apart
      {:ok, _counts} = discover(root)
      {items, _more} = Inbox.list_items(filter: "The Way of Kings")
      assert length(items) == 3
    end

    # The stray-file trap, which is where the folder grain earns its keep: one
    # loose file beside 43 book folders makes the whole series "the release",
    # because audio in hand means this is it. Splitting by folder takes it
    # apart — and the piece left holding the stray file sits on the series
    # folder's own path, which the rescan must not read as "re-record this
    # folder whole".
    test "a series collapsed by a stray file splits, and stays split", %{conn: conn} do
      root = watched_root()
      series = Path.join(root, "Discworld")
      File.mkdir_p!(series)
      File.cp!(tagged_fixture(true, false, nil), Path.join(series, "stray.m4b"))

      for title <- ["Discworld 5 Sourcery", "Discworld 39 Snuff"] do
        dir = Path.join(series, title)
        File.mkdir_p!(dir)
        File.cp!(tagged_fixture(true, false, nil), Path.join(dir, "book.m4b"))
      end

      {:ok, _counts} = discover(root)
      {[item], _more} = Inbox.list_items(filter: "Discworld")
      {:ok, item} = Inbox.probe_item(item)
      Repo.delete_all(Oban.Job)

      assert length(item.files) == 3

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      view |> element("button[data-role='split-folder']") |> render_click()

      {items, _more} = Inbox.list_items(filter: "Discworld")
      assert length(items) == 3

      {:ok, _counts} = discover(root)
      {items, _more} = Inbox.list_items(filter: "Discworld")

      assert length(items) == 3
      # each keeps exactly what it claimed: the two books, and the stray
      assert items |> Enum.map(&length(&1.files)) |> Enum.sort() == [1, 1, 1]
    end
  end

  # The header used to print the item's path over a file list about to print
  # the same string two cards below it.
  describe "where the item is, said once" do
    test "the path goes when the file list states it", %{conn: conn} do
      item = probed_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "[data-role='item-path']")
      # still on the page: the list prints the folder its files share
      assert html =~ "The Way of Kings [M4B]"
    end

    # A loose file at the top of a watched folder has no directory above it,
    # and the list printed "./" for one until it stopped answering "." to a
    # question about where something is.
    test "a loose file is its own path, printed once and without a directory",
         %{conn: conn} do
      root = watched_root()
      File.cp!(tagged_fixture(true, false, nil), Path.join(root, "Loose Book.m4b"))

      {:ok, _counts} = discover(root)
      {[item], _more} = Inbox.list_items(filter: "Loose Book")
      {:ok, item} = Inbox.probe_item(item)
      Repo.delete_all(Oban.Job)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "[data-role='item-path']")
      refute html =~ "./"
    end

    # The queue row has carried the watched folder since the queue could hold
    # more than one; the form is where the paths are actually read.
    test "the source it was found in is on the form, in the row's own tag", %{conn: conn} do
      item = Inbox.get_item!(probed_item().id)

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ item.source.name
    end

    test "the path stays when the files sit deeper than the item", %{conn: conn} do
      root = watched_root()
      disc = Path.join(root, "Some Release/Disc 1")
      File.mkdir_p!(disc)
      File.cp!(tagged_fixture(true, false, nil), Path.join(disc, "01.m4b"))

      {:ok, _counts} = discover(root)
      {[item], _more} = Inbox.list_items(filter: "Some Release")
      {:ok, item} = Inbox.probe_item(item)
      Repo.delete_all(Oban.Job)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      # the list names "Some Release/Disc 1"; which of the two this item is
      # is what a split or a combine is about
      assert has_element?(view, "[data-role='item-path']")
    end

    test "the path stays when there are no files to say it", %{conn: conn} do
      item = probed_item()
      {:ok, item} = Inbox.update_item(item, %{files: []})

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(view, "[data-role='item-path']")
    end
  end

  describe "an item that is gone" do
    # A split or a combine replaces items rather than editing them, so the id
    # in the address bar outlives the item and browser Back walks straight
    # into it. The queue is where that goes, with the list the operator was
    # on kept.
    test "lands back in the queue rather than on a 404", %{conn: conn} do
      item = probed_item()
      id = item.id
      Repo.delete!(item)

      assert {:error, {kind, %{to: to, flash: flash}}} = live(conn, ~p"/admin/inbox/#{id}")
      assert kind in [:redirect, :live_redirect]
      assert to == ~p"/admin/inbox"
      assert flash["info"] =~ "gone"

      assert {:error, {_kind, %{to: to}}} =
               live(conn, ~p"/admin/inbox/#{id}?#{[status: "ignored", page: "2"]}")

      assert to == ~p"/admin/inbox?#{[page: "2", status: "ignored"]}"
    end
  end

  # A release that ships the same part twice, which nothing but a listener
  # can spot: the file list is where it is seen, so it is where it is fixed.
  describe "taking one file out of the audiobook" do
    setup %{conn: conn} do
      root = watched_root()
      release = Path.join(root, "Oathbringer")
      File.mkdir_p!(release)

      for name <- ["P05.m4b", "P06.m4b", "P06_CD.m4b"] do
        File.cp!(tagged_fixture(true, false, nil), Path.join(release, name))
      end

      {:ok, _counts} = discover(root)
      {[item], _more} = Inbox.list_items(filter: "Oathbringer")
      {:ok, item} = Inbox.probe_item(item)
      Repo.delete_all(Oban.Job)

      %{conn: conn, item: item}
    end

    test "the ✕ on a row takes it out, and the row says so", %{conn: conn, item: item} do
      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      # nothing is out, so nothing is counted
      refute has_element?(view, "[data-role='excluded-count']")
      refute html =~ "not in this audiobook"

      view
      |> element("button[phx-value-file='Oathbringer/P06_CD.m4b']")
      |> render_click()

      assert Inbox.get_item!(item.id).excluded_files == ["Oathbringer/P06_CD.m4b"]

      html = render(view)
      assert html =~ "2 of 3 in this audiobook"
      assert html =~ "not in this audiobook"

      # still listed, because the folder still holds it
      assert html =~ "P06_CD.m4b"
    end

    test "and the same control puts it back", %{conn: conn, item: item} do
      {:ok, item} = Inbox.exclude_file(item, "Oathbringer/P06_CD.m4b")
      # the re-read that excluding queues has finished; without this the form
      # is busy and refuses every event, which is the point of the overlay
      Repo.delete_all(Oban.Job)

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      assert has_element?(view, "[data-role='excluded-file']")

      view
      |> element("button[phx-value-file='Oathbringer/P06_CD.m4b']")
      |> render_click()

      assert Inbox.get_item!(item.id).excluded_files == []
      refute has_element?(view, "[data-role='excluded-file']")
    end

    test "an imported item's files are read-only", %{conn: conn, item: item} do
      {:ok, item} = Inbox.prepare_draft(item)
      {:ok, item} = Inbox.update_item(item, %{status: :imported})

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      refute has_element?(view, "button[phx-value-file]")
    end
  end

  describe "combining items that are one audiobook" do
    # The operator's real case, and the mirror of the split above: three
    # subfolders holding one audiobook, named so that nothing but a human
    # could tell them from three books. The walk offers three items; the
    # correction has to be reachable from any one of them.
    test "the combine button makes one item of the folder", %{conn: conn} do
      root = watched_root()
      book = Path.join(root, "Gwendy's Button Box by Stephen King & Richard Chizmar")

      for part <- 1..3, track <- 1..2 do
        dir = Path.join(book, "Gwendy's Button Box #{part}")
        File.mkdir_p!(dir)
        File.cp!(tagged_fixture(true, false, nil), Path.join(dir, "Track0#{track}.mp3"))
      end

      {:ok, _counts} = discover(root)
      {items, _more} = Inbox.list_items(filter: "Gwendy")
      assert length(items) == 3

      item = Enum.find(items, &(InboxItem.name(&1) == "Gwendy's Button Box 1"))
      {:ok, item} = Inbox.probe_item(item)
      Repo.delete_all(Oban.Job)

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Only part of one?"
      assert html =~ "Combine 3 items into one"

      view |> element("button[data-role='combine']") |> render_click()
      {path, _flash} = assert_redirect(view)

      {[combined], _more} = Inbox.list_items(filter: "Gwendy")
      assert path == ~p"/admin/inbox/#{combined}"
      assert InboxItem.name(combined) == "Gwendy's Button Box by Stephen King & Richard Chizmar"
      assert length(combined.files) == 6

      # and the folder now holds one item, so there is nothing left to offer
      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{combined}")
      refute html =~ "Only part of one?"
    end

    # Every item at the top of a watched folder shares the watched folder,
    # and an item there would own everything that ever lands in it.
    test "a release of its own is offered nothing", %{conn: conn} do
      item = probed_item()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      refute html =~ "Only part of one?"
    end
  end

  describe "destination" do
    test "is two pickers and no prose", %{conn: conn} do
      item = probed_item(policy: :symlink) |> settle()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert html =~ "Library root"
      assert html =~ "How the files come in"

      # What import will do is the pickers' own values. Restating it in a
      # sentence underneath is noise on every visit after the first.
      refute html =~ "Symlinked into"
      refute html =~ "dangles if the original"
      refute html =~ "duplicating the bytes"
    end

    # The options name the four doors. They used to define them too, which
    # is a thing you read once and then re-read on every import forever.
    test "the pickers name things rather than define them", %{conn: conn} do
      item = probed_item() |> settle()

      {:ok, _view, html} = live(conn, ~p"/admin/inbox/#{item}")

      for door <- ~w(Hardlink Symlink Copy Move), do: assert(html =~ door)
      refute html =~ "same filesystem only"
      refute html =~ "empties the source folder"

      # A root name is unique, so the path underneath it identified nothing
      # the name didn't.
      [root] = Ambry.Library.list_roots()
      assert html =~ root.name
      refute html =~ "#{root.name} (#{root.path})"
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
        "cover_url" => Keyword.get(opts, :covers, %{})[id],
        "score" => Keyword.get(opts, :scores, %{})[id] || if(id == "hc-1", do: 0.95, else: 0.6)
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

  defp folded_records(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='worse-matches'] [data-role='record'] input[type='checkbox']")
    |> Enum.flat_map(&Floki.attribute([&1], "phx-value-id"))
  end

  defp used_records(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='record'][data-used='true']")
  end

  # Two humans behind one credit, the way the form now asks it: the composite
  # case IS a shared pen name, so the add sits on the person's card and only
  # once the credited name has been called one.
  defp add_second_person(view, key) do
    view |> element("#person-#{key} button[phx-click='separate-name']") |> render_click()
    view |> element("#person-#{key} button[phx-click='add-person']") |> render_click()
  end

  # Every item comes from a source; get-or-create so a rescan of the same
  # tree is still one source.
  defp discover(root) do
    source =
      Repo.get_by(Ambry.Library.Source, path: root) || insert(:source, path: root)

    Inbox.discover(source)
  end

  defp watched_root do
    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)
    root
  end

  defp person_keyed(item, key) do
    Enum.find(Inbox.get_item!(item.id).draft.people, &(&1.key == key))
  end

  # What a search form's text boxes are actually holding, which is the whole
  # question when a search is in flight.
  defp search_values(html, selector) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#{selector} input[type='text']")
    |> Map.new(fn input ->
      {Floki.attribute(input, "name") |> hd(), Floki.attribute(input, "value") |> hd()}
    end)
  end

  # A draft whose book is already in the library and already has a set, which
  # is the only way candidates are non-empty: `Seed.book_groups/1` needs a
  # linked work to have a book to ask about.
  defp item_with_candidate_set do
    {:ok, item} = Inbox.prepare_draft(probed_item())
    book = insert(:book)
    group = insert(:recording_group, book: book, name: "GraphicAudio", parts_total: 2)

    link = %Draft.GroupLink{
      mode: :create,
      name: "GraphicAudio",
      proposed_name: "GraphicAudio",
      part_number: 1,
      source: "local",
      candidates: [
        %Draft.GroupLink.Match{
          recording_group_id: group.id,
          name: group.name,
          parts_total: group.parts_total
        }
      ]
    }

    draft = put_in(item.draft, [Access.key(:recording), Access.key(:recording_group)], link)
    {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

    %{item: item, book: book, group: group}
  end

  defp have_way_of_kings do
    insert(:book,
      title: "The Way of Kings",
      book_authors: [build(:book_author, author: build(:author, name: "Brandon Sanderson"))]
    )
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

    # A settled destination needs a root to place into. Root and fixtures
    # share a filesystem here, so the policy defaults to hardlinking, which
    # leaves the fixtures where the test put them.
    if Ambry.Library.list_roots() == [] do
      library = Ambry.Paths.source_media_disk_path("library-#{Ecto.UUID.generate()}")
      File.mkdir_p!(library)
      insert(:root, path: library)
    end

    watched = insert(:source, path: root, name: "Watched #{Ecto.UUID.generate()}")

    # The policy lives on the pairing now. Root and fixtures share a
    # filesystem here, so it would default to hardlinking; a test that wants
    # a different door seeds it the way an earlier import would have.
    if policy = Keyword.get(opts, :policy) do
      {:ok, _memory} =
        Ambry.Library.remember_placement(watched, hd(Ambry.Library.list_roots()), policy)
    end

    {:ok, _counts} = Inbox.discover(watched)
    {items, _more} = Inbox.list_items(filter: name)
    {:ok, item} = items |> hd() |> Inbox.probe_item()

    # Probing enqueues matching, and `testing: :manual` means it never runs —
    # so the item would look permanently *busy* and the form would refuse
    # every event. Clearing the job is what "matching has finished" looks
    # like from `Progress`'s point of view. Tests that care about the busy
    # state put a job back.
    if !Keyword.get(opts, :busy, false), do: Repo.delete_all(Oban.Job)

    with_person_matches(item, Keyword.get(opts, :person_photo))
  end

  # What matching writes when it found people of roughly this name and none of
  # them is this human: candidates, but nothing the exact-name gate will take.
  defp with_namesake_person_matches(item) do
    people = %{
      "brandonsanderson" => %{
        "name" => "Brandon Sanderson",
        "roles" => ["author"],
        "local" => [],
        "candidates" => [
          %{
            "source" => "provider:wikidata",
            "provider_name" => "Wikidata",
            "id" => "Q9",
            "name" => "Brandon Sanderson-Smith",
            "images" => ["https://example.test/somebody-else.jpg"],
            "description" => "An English professional footballer."
          }
        ],
        "providers" => []
      }
    }

    {:ok, item} =
      item
      |> InboxItem.changeset(%{matches: Map.put(item.matches || %{}, "people", people)})
      |> Repo.update()

    item
  end

  # What matching writes when the credited name is already in the library: it
  # searches nothing, because the library's own photo and biography are what
  # an existing person is for.
  defp with_local_person(item, person) do
    people = %{
      "brandonsanderson" => %{
        "name" => "Brandon Sanderson",
        "roles" => ["author"],
        "local" => [
          %{
            "source" => "local",
            "id" => person.id,
            "name" => person.name,
            "has_image" => false,
            "has_description" => false
          }
        ],
        "candidates" => [],
        "providers" => []
      }
    }

    {:ok, item} =
      item
      |> InboxItem.changeset(%{matches: Map.put(item.matches || %{}, "people", people)})
      |> Repo.update()

    item
  end

  # What the people level of matching would have written. Stubbing it here
  # rather than running it keeps the form tests off the network, the same way
  # the work and recording levels are handled.
  defp with_person_matches(item, nil), do: item

  defp with_person_matches(item, photo) do
    people = %{
      "brandonsanderson" => %{
        "name" => "Brandon Sanderson",
        "roles" => ["author"],
        "local" => [],
        "candidates" => [
          %{
            "source" => "provider:wikidata",
            "provider_name" => "Wikidata",
            "id" => "Q1",
            "name" => "Brandon Sanderson",
            "images" => [photo],
            "description" => "An American author of epic fantasy."
          }
        ]
      }
    }

    {:ok, item} =
      item
      |> Ambry.Inbox.InboxItem.changeset(%{
        matches: Map.put(item.matches || %{}, "people", people)
      })
      |> Ambry.Repo.update()

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
