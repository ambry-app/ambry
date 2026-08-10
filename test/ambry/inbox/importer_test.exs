defmodule Ambry.Inbox.ImporterTest do
  use Ambry.DataCase
  use Patch

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Media
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person

  describe "approve/1" do
    test "creates the whole graph from a tagged file" do
      item = tagged_item()

      assert {:ok, media} = Inbox.import_item(item)

      media = media.id |> Media.get_media!() |> Repo.preload(:narrators)
      book = Books.get_book!(media.book_id)

      assert book.title == "The Way of Kings"
      assert [%{name: "Brandon Sanderson"}] = book.authors
      assert [%{name: "Michael Kramer"}, %{name: "Kate Reading"}] = media.narrators
      assert [track] = media.media_tracks
      assert track.codec == "aac"
      assert Decimal.compare(media.duration, 0) == :gt
    end

    test "references the files where they lie and never touches them" do
      item = tagged_item()
      [file] = item.files
      before = File.stat!(file)

      assert {:ok, media} = Inbox.import_item(item)

      assert media.custody == :external
      assert media.source_files == item.files
      assert [%{path: ^file}] = Media.get_media!(media.id).media_tracks

      assert File.exists?(file)
      assert File.stat!(file).size == before.size
    end

    test "does not publish" do
      assert {:ok, media} = tagged_item() |> Inbox.import_item()

      assert media.status == :pending
    end

    test "marks the item approved and links it to what it became" do
      item = tagged_item()

      assert {:ok, media} = Inbox.import_item(item)

      item = Inbox.get_item!(item.id)
      assert item.status == :imported
      assert item.media_id == media.id
    end

    test "won't approve the same item twice" do
      item = tagged_item()
      {:ok, _media} = Inbox.import_item(item)

      assert {:error, :already_imported} = item.id |> Inbox.get_item!() |> Inbox.import_item()
    end

    # The status check at the door reads the caller's copy of the item, so a
    # caller holding a stale :pending struct walked straight through it —
    # measured live as two concurrent approvals, where the loser rolled back
    # AFTER its 834MB copy landed and the orphan refused the item forever.
    # The claim under the row lock is what actually decides.
    test "a stale caller cannot approve an already-approved item" do
      item = tagged_item()
      stale = item

      {:ok, _media} = Inbox.import_item(item)

      assert {:error, :already_imported} = Inbox.import_item(stale)
    end

    # Occupied-by-a-recording and occupied-by-a-leftover need opposite
    # advice, and the old message sent the operator hunting for a second
    # recording that did not exist.
    test "an occupied destination says whether the occupant is an orphan" do
      {:ok, media} = tagged_item() |> Inbox.import_item()
      [track] = Media.get_media!(media.id).media_tracks

      assert Inbox.describe_error({:destination_exists, track.path}) =~
               "can't share one path"

      assert Inbox.describe_error({:destination_exists, "/library/nowhere.m4b"}) =~
               "nothing in the library references"
    end
  end

  describe "approve/1 and existing records" do
    test "reuses a Book already in the library rather than duplicating the work" do
      existing = insert(:book, title: "The Way of Kings")
      item = tagged_item(work_match: {"local", existing.id})

      assert {:ok, media} = Inbox.import_item(item)

      assert media.book_id == existing.id
      assert Repo.aggregate(Book, :count) == 1
    end

    test "reuses an existing author instead of creating a second one" do
      person = insert(:person, name: "Brandon Sanderson")
      author = insert(:author, person: person, name: "Brandon Sanderson")

      assert {:ok, media} = tagged_item() |> Inbox.import_item()

      book = Books.get_book!(media.book_id)
      assert [%{id: author_id}] = book.authors
      assert author_id == author.id
      assert Repo.aggregate(Author, :count) == 1
    end

    # 3b's promise is that the operator never leaves the inbox to finish a
    # leaf entity, and a person with no face is unfinished.
    test "a new person arrives with the bio and photo picked in the inbox" do
      %{web_path: web_path} = Ambry.Factory.valid_image(:person)
      patch(Ambry.Images, :import_url, fn _url -> {:ok, web_path} end)

      item = tagged_item() |> Inbox.prepare_draft() |> then(fn {:ok, item} -> item end)

      item =
        update_in(item.draft.people, fn people ->
          Enum.map(people, fn person ->
            if person.key == "brandonsanderson" do
              %{
                person
                | description: picked("An American author of epic fantasy.", "provider:wikidata"),
                  image: picked("https://example.test/headshot.jpg", "provider:tmdb")
              }
            else
              person
            end
          end)
        end)

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(item.draft))

      assert {:ok, media} = item |> settle() |> Inbox.import_item()

      book = media.book_id |> Books.get_book!() |> Repo.preload(authors: :people)
      assert [%{people: [person]}] = book.authors
      assert person.description == "An American author of epic fantasy."
      assert person.image_path == web_path

      # picked from a provider: that provider's source, and unlocked so a
      # later refresh may still improve it
      assert %{"source" => "provider:tmdb", "locked" => false} =
               Ambry.Provenance.entry(person, :image_path)

      assert %{"source" => "provider:wikidata"} = Ambry.Provenance.entry(person, :description)
    end

    test "creates a person alongside a brand-new narrator credit" do
      assert {:ok, media} = tagged_item() |> Inbox.import_item()

      media = media.id |> Media.get_media!() |> Repo.preload(:narrators)

      assert [first | _rest] = media.narrators
      assert Repo.get!(Narrator, first.id).person_id
    end

    # An author reading their own book is one human wearing two hats. The
    # author credit and the narrator credit have no idea about each other, so
    # each created its own Person and the library got two Brandon Sandersons —
    # one with the photo and bio, one without.
    test "an author who narrates their own book is created once" do
      item = tagged_item(narrator: "Brandon Sanderson")

      assert {:ok, media} = Inbox.import_item(item)

      assert [person] = Repo.all(where(Person, name: "Brandon Sanderson"))

      book = Books.get_book!(media.book_id)
      assert [author] = book.authors

      assert [author_person] =
               Repo.get!(Author, author.id) |> Repo.preload(:people) |> Map.get(:people)

      assert author_person.id == person.id

      media = media.id |> Media.get_media!() |> Repo.preload(:narrators)
      assert [narrator] = media.narrators
      assert Repo.get!(Narrator, narrator.id).person_id == person.id
    end

    test "saying they are two different people of one name creates both" do
      item = tagged_item(narrator: "Brandon Sanderson")

      draft = Draft.Edit.split_person(item.draft, item, :recording, 0, 0)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))
      item = settle(item)

      assert {:ok, _media} = Inbox.import_item(item)

      assert [_one, _other] = Repo.all(where(Person, name: "Brandon Sanderson"))
    end

    # Whichever row the operator went looking on, the one person gets what was
    # found — they were finding a photo of a human, not decorating a row.
    test "a photo found on one credit reaches the person created for both" do
      item = tagged_item(narrator: "Brandon Sanderson")

      item =
        update_in(item.draft.people, fn people ->
          Enum.map(
            people,
            &%{&1 | image: picked("https://example.test/face.jpg", "provider:tmdb")}
          )
        end)

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(item.draft))

      %{web_path: web_path} = Ambry.Factory.valid_image(:person)
      patch(Ambry.Images, :import_url, fn _url -> {:ok, web_path} end)

      assert {:ok, _media} = Inbox.import_item(item)

      assert [person] = Repo.all(where(Person, name: "Brandon Sanderson"))
      assert person.image_path == web_path
    end
  end

  # A settled field the operator picked from a provider, which is what the
  # picker leaves behind.
  defp picked(value, source) do
    %Ambry.Inbox.Draft.Field{
      value: value,
      source: source,
      chosen_key: source,
      approved: true
    }
  end

  # A draft is a snapshot of the library taken when the item was matched, and
  # approval executes it exactly — so two queued items implying the same new
  # human each created their own. Measured on a real batch of seven: Em
  # Grosland narrates both Monk & Robot books and arrived as two People and
  # two Narrators, and "Monk and Robot" arrived as two Series.
  describe "two queued items that share a new entity" do
    test "the second links what the first created, rather than duplicating it" do
      first = tagged_item(narrator: "Em Grosland")
      second = tagged_item(name: "Another Release", narrator: "Em Grosland")

      assert {:ok, _media} = Inbox.import_item(first)

      # the refresh has re-derived the sibling: its narrator credit now points
      # at the identity that exists, and says so on the form
      second = Inbox.get_item!(second.id)
      assert [credit] = second.draft.recording.narrators
      assert credit.mode == :link
      assert credit.identity_id

      assert {:ok, _media} = Inbox.import_item(settle(second))

      assert [_only_one] = Repo.all(where(Person, name: "Em Grosland"))
      assert [_only_one] = Repo.all(where(Narrator, name: "Em Grosland"))
    end

    # The same rule for the work itself — the split-library case the whole
    # work-identity design exists to prevent. Two queued releases of one book
    # each matched against a library that didn't have it; importing the first
    # must re-point the second at the Book that now exists.
    test "the second recording of one work links the book the first created" do
      first = tagged_item(narrator: "Em Grosland")
      second = tagged_item(name: "A Better Rip", narrator: "Em Grosland")

      assert {:ok, _media} = Inbox.import_item(first)

      second = Inbox.get_item!(second.id)
      assert second.draft.work.mode == :link
      assert second.draft.work.book_id

      assert {:ok, _media} = Inbox.import_item(settle(second))
      assert Repo.aggregate(Book, :count) == 1
    end

    test "an identity the operator settled as new stays new" do
      first = tagged_item(narrator: "Em Grosland")
      second = tagged_item(name: "A Deliberate Twin", narrator: "Em Grosland")

      {:ok, second} = Inbox.prepare_draft(second)
      draft = Draft.Edit.new_book(second.draft, second)
      {:ok, _} = Inbox.update_draft(second, Inbox.dump_draft(draft))

      assert {:ok, _media} = Inbox.import_item(first)

      second = Inbox.get_item!(second.id)
      assert second.draft.work.mode == :create
    end

    # Anything a human touched is theirs. Re-derivation may not quietly
    # relink a credit the operator deliberately set to create.
    test "a curated credit is left exactly as the operator left it" do
      first = tagged_item(narrator: "Em Grosland")
      second = tagged_item(name: "Another Release", narrator: "Em Grosland")

      {:ok, second} = Inbox.prepare_draft(second)
      draft = Draft.Edit.approve_credit(second.draft, :recording, 0, true)
      {:ok, _} = Inbox.update_draft(second, Inbox.dump_draft(draft))

      assert {:ok, _media} = Inbox.import_item(first)

      second = Inbox.get_item!(second.id)
      assert [credit] = second.draft.recording.narrators
      assert credit.curated
      assert credit.mode == :create
    end
  end

  describe "part-of-a-set numbers" do
    # A part-release (GraphicAudio's "Part 1 of 2") is an ordinary separate
    # recording — its own cover, date, narrators, sometimes sold separately —
    # that happens to carry the optional part label. The operator types the
    # numbers; nothing proposes them, and grouping the parts into one set
    # stays on the media form.
    test "typed part numbers reach the imported media" do
      item = tagged_item()

      draft = %{
        item.draft
        | recording: %{item.draft.recording | part_number: 1, parts_total: 2}
      }

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      assert {:ok, media} = Inbox.import_item(item)

      media = Media.get_media!(media.id)
      assert media.part_number == 1
      assert media.parts_total == 2
      # no group is invented — tying the set together is the media form's job
      assert media.recording_group_id == nil
    end

    test "the numbers count as curation, so a re-match can't discard them" do
      item = tagged_item(settle: false)
      {:ok, item} = Inbox.prepare_draft(item)

      draft = %{
        item.draft
        | recording: %{item.draft.recording | part_number: 1, parts_total: 2}
      }

      assert Draft.curated?(draft)
    end
  end

  describe "approve/1 refusals" do
    test "refuses a multi-file release rather than importing half of it" do
      # Checked before the draft: no amount of curation makes a multi-file
      # release importable — the operator splits it into one item per file.
      item = tagged_item(files: ["01.mp3", "02.mp3"], settle: false)

      assert {:error, :multi_file_unsupported} = Inbox.import_item(item)
      assert Repo.aggregate(Book, :count) == 0
    end

    # A work must have a publication date and the inbox has no business
    # inventing one — matching a work supplies it, as does tagging the file.
    test "keeps a matched work's date granularity instead of inventing a release day" do
      selection = %{
        "source" => "provider:x",
        "id" => "1",
        "title" => "Project Hail Mary",
        "published" => "2021-01-01",
        "published_format" => "year",
        "score" => 1.0
      }

      item = tagged_item(dated: false, work_match: selection)

      assert {:ok, media} = Inbox.import_item(item)

      book = Books.get_book!(media.book_id)
      assert book.published == ~D[2021-01-01]
      assert book.published_format == :year
    end

    # The refusal that used to be thrown at the last moment is now a decision
    # the operator can see in the form — a missing publication date is
    # something to supply, not a mystery at the point of clicking import.
    test "refuses a release with no publication date anywhere" do
      item = tagged_item(dated: false, settle: false)
      {:ok, item} = Inbox.prepare_draft(item)

      assert {:error, {:unresolved, outstanding}} = Inbox.import_item(item)
      assert Enum.any?(outstanding, &(&1.label == "First published" and &1.state == :missing))
      assert Repo.aggregate(Book, :count) == 0
    end

    test "a required decision cannot be waived into approval" do
      item = tagged_item(dated: false, settle: false)
      {:ok, item} = Inbox.prepare_draft(item)

      assert {:error, changeset} =
               Inbox.update_draft(item, %{
                 "work" => %{
                   "published" => %{"value" => "", "approved" => true, "required" => true}
                 }
               })

      refute changeset.valid?
    end

    @tag :capture_log
    test "refuses a file that vanished between discovery and approval" do
      item = tagged_item()
      item.files |> hd() |> File.rm!()

      assert {:error, {:unreadable, _reason}} = Inbox.import_item(item)

      # nothing half-created, and the item stays in the queue
      assert Repo.aggregate(Book, :count) == 0
      assert Inbox.get_item!(item.id).status == :pending
    end
  end

  # A real tagged file discovered the way discovery would find it.
  defp tagged_item(opts \\ []) do
    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    name = Keyword.get(opts, :name, "The Way of Kings [M4B]")
    release = Path.join(root, name)
    File.mkdir_p!(release)

    case Keyword.get(opts, :files) do
      nil ->
        File.cp!(
          tagged_fixture(Keyword.get(opts, :dated, true), Keyword.get(opts, :narrator)),
          Path.join(release, "book.m4b")
        )

      names ->
        Enum.each(names, &File.cp!(valid_audio(:mp3), Path.join(release, &1)))
    end

    {:ok, _counts} = Inbox.discover(root)
    {[item], false} = Inbox.list_items(filter: name)
    {:ok, item} = Inbox.probe_item(item)

    item =
      case Keyword.get(opts, :work_match) do
        nil ->
          item

        match ->
          # A Book already in the library is a different kind of answer from a
          # provider record, so it goes in its own list.
          work =
            case match do
              {"local", id} ->
                %{
                  "candidates" => [],
                  "local" => [%{"id" => id, "score" => 1.0}],
                  "confidence" => 1.0
                }

              %{} = provider ->
                %{"candidates" => [provider], "local" => [], "confidence" => 1.0}
            end

          {:ok, item} =
            Inbox.update_item(item, %{
              matches: %{"work" => work, "recording" => %{"candidates" => []}}
            })

          item
      end

    # Approval executes a resolved draft, so getting an item to the state the
    # import form would leave it in is now part of arranging any approval
    # test. `settle: false` is for the tests that care about what happens when
    # it isn't.
    if Keyword.get(opts, :settle, true), do: settle(item), else: item
  end

  defp tagged_fixture(dated?, narrator) do
    dir = Ambry.Paths.source_media_disk_path("fixture-#{Ecto.UUID.generate()}")
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
        ] ++ if(dated?, do: ["-metadata", "date=2010-08-31"], else: []) ++ [path]
      )

    path
  end
end
