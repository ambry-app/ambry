defmodule Ambry.Inbox.ApprovalTest do
  use Ambry.DataCase
  use Patch

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Inbox
  alias Ambry.Media
  alias Ambry.People.Author
  alias Ambry.People.Narrator

  describe "approve/1" do
    test "creates the whole graph from a tagged file" do
      item = tagged_item()

      assert {:ok, media} = Inbox.approve_item(item)

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

      assert {:ok, media} = Inbox.approve_item(item)

      assert media.custody == :external
      assert media.source_files == item.files
      assert [%{path: ^file}] = Media.get_media!(media.id).media_tracks

      assert File.exists?(file)
      assert File.stat!(file).size == before.size
    end

    test "does not publish" do
      assert {:ok, media} = tagged_item() |> Inbox.approve_item()

      assert media.status == :pending
    end

    test "marks the item approved and links it to what it became" do
      item = tagged_item()

      assert {:ok, media} = Inbox.approve_item(item)

      item = Inbox.get_item!(item.id)
      assert item.status == :approved
      assert item.media_id == media.id
    end

    test "won't approve the same item twice" do
      item = tagged_item()
      {:ok, _media} = Inbox.approve_item(item)

      assert {:error, :already_approved} = item.id |> Inbox.get_item!() |> Inbox.approve_item()
    end
  end

  describe "approve/1 and existing records" do
    test "reuses a Book already in the library rather than duplicating the work" do
      existing = insert(:book, title: "The Way of Kings")
      item = tagged_item(work_match: {"local", existing.id})

      assert {:ok, media} = Inbox.approve_item(item)

      assert media.book_id == existing.id
      assert Repo.aggregate(Book, :count) == 1
    end

    test "reuses an existing author instead of creating a second one" do
      person = insert(:person, name: "Brandon Sanderson")
      author = insert(:author, person: person, name: "Brandon Sanderson")

      assert {:ok, media} = tagged_item() |> Inbox.approve_item()

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
        update_in(item.draft.work.authors, fn [credit | rest] ->
          [
            %{
              credit
              | people: [
                  %Ambry.Inbox.Draft.PersonRef{
                    name: "Brandon Sanderson",
                    description: "An American author of epic fantasy.",
                    description_source: "provider:wikidata",
                    image_url: "https://example.test/headshot.jpg",
                    image_source: "provider:tmdb"
                  }
                ]
            }
            | rest
          ]
        end)

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(item.draft))

      assert {:ok, media} = item |> settle() |> Inbox.approve_item()

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
      assert {:ok, media} = tagged_item() |> Inbox.approve_item()

      media = media.id |> Media.get_media!() |> Repo.preload(:narrators)

      assert [first | _rest] = media.narrators
      assert Repo.get!(Narrator, first.id).person_id
    end
  end

  describe "approve/1 refusals" do
    test "refuses a multi-file release rather than importing half of it" do
      # Checked before the draft: no amount of curation makes a multi-file
      # release importable, so the operator must not be sent to the form.
      item = tagged_item(files: ["01.mp3", "02.mp3"], settle: false)

      assert {:error, :multi_file_unsupported} = Inbox.approve_item(item)
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

      assert {:ok, media} = Inbox.approve_item(item)

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

      assert {:error, {:unresolved, outstanding}} = Inbox.approve_item(item)
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

      assert {:error, {:unreadable, _reason}} = Inbox.approve_item(item)

      # nothing half-created, and the item stays in the queue
      assert Repo.aggregate(Book, :count) == 0
      assert Inbox.get_item!(item.id).status == :pending
    end
  end

  # A real tagged file discovered the way discovery would find it.
  defp tagged_item(opts \\ []) do
    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    release = Path.join(root, "The Way of Kings [M4B]")
    File.mkdir_p!(release)

    case Keyword.get(opts, :files) do
      nil ->
        File.cp!(
          tagged_fixture(Keyword.get(opts, :dated, true)),
          Path.join(release, "book.m4b")
        )

      names ->
        Enum.each(names, &File.cp!(valid_audio(:mp3), Path.join(release, &1)))
    end

    {:ok, _counts} = Inbox.discover(root)
    {[item], false} = Inbox.list_items()
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

  defp tagged_fixture(dated?) do
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
          "composer=Michael Kramer, Kate Reading"
        ] ++ if(dated?, do: ["-metadata", "date=2010-08-31"], else: []) ++ [path]
      )

    path
  end
end
