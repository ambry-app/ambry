defmodule Ambry.Inbox.Importer do
  @moduledoc """
  Turns a fully-resolved staged import into real library records.

  Import is the only thing that creates records — discovery, matching and
  the form only ever propose. It covers the whole entity graph in one
  transaction: book, authors, narrators, series, the recording and its
  direct-play tracks. Either all of it lands or none of it does, so a
  half-imported item can't exist.

  ## It executes a draft; it does not decide anything

  Every choice was made in `Ambry.Inbox.Draft` and settled by the operator (or
  by a seeding rule confident enough to settle it). This module refuses
  outright unless `Draft.resolved?/1`, then does exactly what the draft says.
  That is the point of the whole design: the form cannot offer a button that
  fails here, because everything that could fail was a visible decision
  before the button was pressed.

  Consequently there are no fallbacks here. If the draft doesn't say what the
  title is, that is a bug in the form's gating, not something to paper over
  with a guess — and inventing a series number or a publication date is
  exactly the confidently-wrong data the inbox exists to prevent.

  ## Custody

  Where an item came from decides what happens to its bytes:

    * from a **bring-in** source, the file is placed into a library root
      under the naming template — hardlinked, copied or moved per the
      source's policy — and the recording becomes **managed**.
    * from a **trusted** source, from inside a library root, or from an item
      with no source at all, the file is referenced exactly where it lies
      and the recording is **external**. Ambry never moves, copies, renames
      or deletes it.

  A hardlink cannot cross a filesystem, and here the downloads folder and the
  library can easily be on different NAS boxes. Import **refuses** in that
  case rather than falling back to a copy: a silent copy is the storage
  doubling this whole phase exists to eliminate.

  ## Provenance

  Every scalar the draft settled knows which source settled it, so
  `field_provenance` is written by construction — a provider-accepted value
  records that provider and stays unlocked so refresh can update it later, an
  operator's typed value records `manual` and locks. This is what closes 1d's
  loop for the inbox without a separate hint-collection layer.
  """

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Images
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library.NamingTemplate
  alias Ambry.Library.Placement
  alias Ambry.Library.Root
  alias Ambry.Media
  alias Ambry.Media.Scanner
  alias Ambry.People
  alias Ambry.People.Author
  alias Ambry.People.AuthorPerson
  alias Ambry.People.Narrator
  alias Ambry.Repo
  alias Ambry.Settings

  require Logger

  @doc """
  Imports an item, creating everything its draft implies.

  Returns `{:ok, media}`, or `{:error, reason}` — leaving the item untouched
  and the library unchanged.
  """
  def import_item(%InboxItem{status: :imported}), do: {:error, :already_imported}

  def import_item(%InboxItem{} = item) do
    item = Repo.preload(item, :source)

    # Facts about the files come first, then the draft, then placement. The
    # order is the order the operator can act on them: a multi-file release or
    # a vanished file is not something any amount of curation fixes, so
    # reporting an unresolved decision on one would send them to the form to
    # fix something the form can't fix.
    with {:ok, file} <- single_file(item),
         {:ok, probe} <- probe(file),
         :ok <- resolved(item),
         {:ok, destination} <- destination(item),
         {:ok, {media, placement}} <- create(item, file, probe, destination) do
      # Only now, with the records committed, is it safe to remove a moved
      # file's source.
      log_finalize(Placement.finalize(placement), item)
      {:ok, media}
    end
  end

  # Import is claimed under a row lock before anything is created or any
  # byte moves. The status check at the door reads the *caller's* copy of
  # the item, so two concurrent imports both walked through it — measured
  # live: the loser's transaction rolled back AFTER its 834MB copy had
  # landed, and the orphan then refused the item forever with a message
  # blaming a phantom second recording. Under the lock the second import
  # waits, sees the committed status, and refuses cleanly.
  defp claim(%InboxItem{id: id}) do
    import Ecto.Query, only: [from: 2]

    case Repo.one(from(i in InboxItem, where: i.id == ^id, lock: "FOR UPDATE")) do
      %InboxItem{status: :pending} = item -> {:ok, Repo.preload(item, :source)}
      %InboxItem{} -> {:error, :already_imported}
      nil -> {:error, :already_imported}
    end
  end

  # The invariant, enforced at the one place it has teeth. Anything the
  # operator hasn't settled is a refusal, not a default.
  defp resolved(%InboxItem{draft: draft}) do
    case Draft.unresolved(draft) do
      [] -> :ok
      outstanding -> {:error, {:unresolved, outstanding}}
    end
  end

  # Placement is deliberately the LAST thing inside the transaction, with
  # nothing but the commit after it. Fail earlier and no bytes have moved;
  # fail at the commit and the worst case is a stray file in the library,
  # which the audit tooling surfaces — never a file whose source was already
  # deleted and whose record didn't survive.
  defp create(item, file, probe, destination) do
    Repo.transact(fn ->
      # People first, and for the whole draft at once: the same human can be
      # behind two credits, and each credit creating its own left a
      # self-narrated book with two Person rows of one name.
      with {:ok, item} <- claim(item),
           {:ok, people} <- resolve_people(item.draft),
           {:ok, book} <- resolve_book(item.draft.work, people),
           {:ok, media} <- create_media(item, book, probe, people),
           {:ok, _item} <- link(item, media),
           {:ok, media, placement} <- place(destination, book, media, file),
           {:ok, media} <- publish(media) do
        {:ok, {media, placement}}
      end
    end)
  end

  ## the work

  defp resolve_book(%{mode: :link, book_id: book_id} = work, _people) do
    case Repo.get(Book, book_id) do
      nil -> {:error, :book_not_found}
      book -> add_series(book, Enum.reject(work.series, & &1.removed))
    end
  end

  defp resolve_book(%{mode: :create} = work, people) do
    Books.create_book(
      %{
        title: Field.value(work.title),
        published: Field.date(work.published),
        published_format: Field.atom(work.published_format, :full),
        book_authors: author_params(work.authors, people),
        series_books: series_params(work.series)
      },
      provenance:
        provenance(%{
          "title" => work.title,
          "published" => work.published,
          "published_format" => work.published_format
        })
    )
  end

  # Fill-gaps on a linked book: an import may add a series membership the book
  # doesn't have, never touch one it does. The seeder has already dropped
  # memberships the book already carries, so anything left here is additive.
  defp add_series(book, []), do: {:ok, book}

  defp add_series(book, links) do
    book = Repo.preload(book, series_books: :series)

    existing =
      Enum.map(book.series_books, &%{series_id: &1.series_id, book_number: &1.book_number})

    case Books.update_book(book, %{series_books: existing ++ series_params(links)}) do
      {:ok, book} -> {:ok, book}
      {:error, _changeset} = error -> error
    end
  end

  # Tombstoned rows are the operator saying "not this one" — they stay on the
  # draft for their possible restore and must never reach the library.
  defp author_params(credits, people) do
    credits
    |> Enum.reject(& &1.removed)
    |> Enum.map(fn credit ->
      {:ok, author} = resolve_identity(credit, people)
      %{author_id: author.id}
    end)
  end

  defp series_params(links) do
    links
    |> Enum.reject(& &1.removed)
    |> Enum.map(fn link ->
      {:ok, series} = resolve_series(link)
      %{series_id: series.id, book_number: SeriesLink.decimal(link)}
    end)
  end

  defp resolve_series(%SeriesLink{mode: :link, series_id: id}), do: {:ok, Repo.get!(Series, id)}

  defp resolve_series(%SeriesLink{mode: :create, name: name}),
    do: Books.create_series(%{name: name})

  ## credits

  # The identity is what a credit resolves to — never a Person. Person appears
  # only when creating, and how many of them there are is just the length of
  # the list the operator left behind.
  defp resolve_identity(%Credit{mode: :link, kind: :author, identity_id: id}, _people),
    do: {:ok, Repo.get!(Author, id)}

  defp resolve_identity(%Credit{mode: :link, kind: :narrator, identity_id: id}, _people),
    do: {:ok, Repo.get!(Narrator, id)}

  # An identity's own changeset only casts its name — identities are normally
  # created *through* a Person, which can't express "this pen name is two
  # people". So the link rows go in explicitly. Each `AuthorPerson` in the
  # list is one human behind the credit; the list being longer than one is the
  # entire composite-author case.
  defp resolve_identity(%Credit{mode: :create, kind: :author} = credit, people) do
    with {:ok, author} <- %Author{} |> Author.changeset(%{name: credit.name}) |> Repo.insert() do
      Enum.each(behind(credit, people), fn person ->
        Repo.insert!(%AuthorPerson{author_id: author.id, person_id: person.id})
      end)

      {:ok, author}
    end
  end

  # Narrators stay one-to-one with a Person by design — composite narrator
  # identities aren't a real-world thing — so only the first reference is used
  # and the form caps the control at one.
  defp resolve_identity(%Credit{mode: :create, kind: :narrator} = credit, people) do
    [person | _rest] = behind(credit, people)

    %Narrator{}
    |> Narrator.changeset(%{name: credit.name})
    |> Ecto.Changeset.put_change(:person_id, person.id)
    |> Repo.insert()
  end

  defp behind(%Credit{} = credit, people),
    do: Enum.map(credit.person_keys, &Map.fetch!(people, &1))

  # Every human the draft implies, created once each and returned by key.
  #
  # One decision per human is now the model's own guarantee rather than
  # something reconstructed here: credits reference people by key, so an
  # author who reads their own book is one `PersonDecision` referenced twice
  # and there is nothing left to fold together. The merge this used to do
  # existed only because the two credits each held their own copy.
  defp resolve_people(%Draft{} = draft) do
    Enum.reduce_while(draft.people, {:ok, %{}}, fn person, {:ok, resolved} ->
      case resolve_person(person) do
        {:ok, created} -> {:cont, {:ok, Map.put(resolved, person.key, created)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_person(%PersonDecision{mode: :link, person_id: id}) when not is_nil(id),
    do: {:ok, Repo.get!(People.Person, id)}

  # A new person arrives complete when matching found them a face and a bio,
  # or the operator picked one — 3b's "never has to leave the inbox" is about
  # exactly this, and a person created bare is a trip to the person form
  # afterwards.
  #
  # A photo that won't fetch doesn't fail the import, for the same reason a
  # cover doesn't: the credit is still correct without it.
  defp resolve_person(%PersonDecision{} = person) do
    People.create_person(
      %{
        name: Field.value(person.name),
        description: Field.value(person.description),
        image_path: person_image(Field.value(person.image))
      },
      provenance: person_provenance(person)
    )
  end

  # String keys: `Provenance.track_changes/3` looks sources up by field name.
  # The name is provenanced too. Without it `track_changes/3` sees a changed
  # field with no source and records the only thing left — **manual, locked** —
  # so every person the inbox created claimed to have been typed by hand, and
  # was locked against the refresh that would have improved it.
  defp person_provenance(%PersonDecision{} = person) do
    %{
      "name" => person.name && person.name.source,
      "image_path" => person.image && person.image.source,
      "description" => person.description && person.description.source
    }
    |> Enum.reject(fn {_field, source} -> is_nil(source) end)
    |> Map.new()
  end

  defp person_image(nil), do: nil

  defp person_image(url) when is_binary(url) do
    case Images.import_url(url) do
      {:ok, web_path} when is_binary(web_path) -> web_path
      other -> log_cover(url, other)
    end
  end

  ## the recording

  defp create_media(item, book, probe, people) do
    recording = item.draft.recording

    Media.create_media(
      %{
        book_id: book.id,
        # external until placement says otherwise; a downloads item is
        # repointed to its library copy below
        custody: :external,
        source_path: item.path,
        source_files: item.files,
        status: :pending,
        # The optional part-of-a-set label ("Part 1 of 2"), typed by the
        # operator. Grouping the parts into one set is the media form's job,
        # after each part is imported.
        part_number: recording.part_number,
        parts_total: recording.parts_total,
        duration: probe.duration,
        chapters: probe.chapters,
        media_narrators: narrator_params(recording.narrators, people),
        media_tracks: [track_params(probe)],
        title: Field.value(recording.title),
        published: Field.date(recording.published),
        published_format: Field.atom(recording.published_format, :full),
        publisher: Field.value(recording.publisher),
        description: Field.value(recording.description),
        image_path: cover(recording.cover)
      },
      provenance:
        provenance(%{
          "title" => recording.title,
          "published" => recording.published,
          "published_format" => recording.published_format,
          "publisher" => recording.publisher,
          "description" => recording.description,
          "image_path" => recording.cover
        })
    )
  end

  defp narrator_params(credits, people) do
    credits
    |> Enum.reject(& &1.removed)
    |> Enum.map(fn credit ->
      {:ok, narrator} = resolve_identity(credit, people)
      %{narrator_id: narrator.id}
    end)
  end

  # A cover that can't be fetched is not worth failing an import over — the
  # recording is still correct without one, and the admin form can set it
  # afterwards. It is worth saying so in the log.
  defp cover(%Field{value: nil}), do: nil

  defp cover(%Field{source: "embedded", value: audio_path}) do
    case Images.extract_embedded(audio_path) do
      {:ok, web_path} -> web_path
      {:error, reason} -> log_cover(audio_path, reason)
    end
  end

  defp cover(%Field{value: url}) do
    case Images.import_url(url) do
      {:ok, web_path} when is_binary(web_path) -> web_path
      other -> log_cover(url, other)
    end
  end

  defp log_cover(source, reason) do
    Logger.warning(fn -> "Couldn't bring in the cover from #{source}: #{inspect(reason)}" end)
    nil
  end

  defp track_params(probe) do
    %{
      index: 0,
      path: probe.path,
      size: probe.size,
      mime: probe.mime,
      format: probe.format,
      codec: probe.codec,
      duration: probe.duration,
      start_offset: 0,
      seek_accuracy: probe.seek_accuracy
    }
  end

  ## provenance

  # Each decision already knows where its value came from, so the provenance
  # map is a projection of the draft rather than anything to collect
  # separately. A field the operator typed records `manual` and locks; an
  # accepted provider value records that provider and stays unlocked, so a
  # future refresh may still update it.
  defp provenance(fields) do
    fields
    |> Enum.flat_map(fn
      {_name, nil} -> []
      {_name, %Field{source: nil}} -> []
      {_name, %Field{source: "manual"}} -> []
      {name, %Field{source: source}} -> [{name, source}]
    end)
    |> Map.new()
  end

  ## publishing

  # An imported recording is finished, so it's published — unless the switch
  # says the fleet can't play direct-play media yet, in which case it waits
  # in `pending` and is released when the switch is turned on.
  #
  # The reload is load-bearing: `Media.changeset` reads tracks off the struct
  # to decide whether the legacy paths are required, and an unloaded assoc
  # reads as "no tracks" — which would demand an mp4 path this recording will
  # never have.
  defp publish(media) do
    if Settings.direct_play_publishing?() do
      media
      |> Repo.reload()
      |> Repo.preload(:media_tracks)
      |> Media.update_media(%{status: :ready})
    else
      {:ok, media}
    end
  end

  ## placement

  # What import should do with the bytes, decided by the draft's custody:
  # only a bring-in source's item is placed; a trusted source's files are
  # adopted exactly where they lie (that is the entire promise of external
  # custody). Read off the draft rather than re-derived from the source: any
  # input may feed any output, so which root this import goes to is a
  # decision the operator made (or that resolved silently because there was
  # only one), not a property of where the files were found.
  defp destination(%InboxItem{draft: %{destination: %{custody: :managed} = destination}}) do
    case Repo.get(Root, destination.root_id) do
      %Root{} = root -> {:ok, {root, destination.policy}}
      nil -> {:error, :no_library_root}
    end
  end

  defp destination(%InboxItem{}), do: {:ok, :adopt}

  defp place(:adopt, _book, media, _file), do: {:ok, media, nil}

  defp place({root, policy}, book, media, file) do
    # Forced: a freshly-created book carries its `book_authors` as insert
    # results with the nested `author` unloaded, and a reused one carries
    # nothing at all. Without this every folder silently loses its author
    # segment — the template collapses empty tokens, so it fails quietly
    # rather than raising.
    book = Repo.preload(book, [{:book_authors, :author}, {:series_books, :series}], force: true)
    media = Repo.preload(media, [{:media_narrators, :narrator}], force: true)

    values = Books.naming_values(book, media)

    with {:ok, folder} <- NamingTemplate.render(Settings.library_naming_template(), values),
         {:ok, filename} <- NamingTemplate.filename(values, file, filename_part(media)),
         path = Path.join([root.path, folder, filename]),
         {:ok, placement} <- Placement.place(file, path, policy),
         {:ok, media} <- adopt_managed(media, path) do
      {:ok, media, placement}
    end
  end

  # Two parts of one set are two separate imports into the same book folder;
  # the suffix is what keeps "The Way of Kings.m4b" from colliding with
  # itself when part 2 arrives.
  defp filename_part(%{part_number: nil}), do: nil
  defp filename_part(%{part_number: number, parts_total: total}), do: {number, total}

  # The recording now points at the library copy and Ambry owns those bytes.
  defp adopt_managed(media, path) do
    with {:ok, _track} <- repoint_track(media, path) do
      media
      |> Ecto.Changeset.change(%{
        custody: :managed,
        source_path: Path.dirname(path),
        source_files: [path]
      })
      |> Repo.update()
    end
  end

  defp repoint_track(%{media_tracks: [track | _rest]}, path) do
    track |> Ecto.Changeset.change(%{path: path}) |> Repo.update()
  end

  defp repoint_track(_no_tracks, _path), do: {:error, :no_tracks}

  # A source that couldn't be removed is untidy, not broken: the library copy
  # exists and is recorded. Failing the import here would be worse than
  # saying so.
  defp log_finalize(:ok, _item), do: :ok

  defp log_finalize({:error, reason}, item) do
    Logger.warning(fn ->
      "Imported #{item.path} but couldn't remove the source: #{inspect(reason)}"
    end)
  end

  ## files

  # An import is one file — a recording whose tracks can't be described has
  # no business in the library, and a multi-file item is split into one item
  # per file first.
  defp single_file(%InboxItem{files: [file]}), do: {:ok, file}
  defp single_file(%InboxItem{files: []}), do: {:error, :no_audio_files}
  defp single_file(%InboxItem{}), do: {:error, :multi_file_unsupported}

  # Re-probed rather than trusting what discovery recorded: it costs one
  # ffprobe and buys current track data, plus a file that vanished between
  # discovery and import failing the import instead of creating a
  # recording that points at nothing.
  defp probe(file) do
    case Scanner.probe_file(file, single_file: true) do
      {:ok, probe} -> {:ok, probe}
      {:error, reason} -> {:error, {:unreadable, reason}}
    end
  end

  defp link(item, media) do
    # issue: nil — a failed attempt writes its reason onto the item so the
    # row can explain itself tomorrow; succeeding is what resolves it. Left
    # in place, "Couldn't add this to the library" sat in red on rows whose
    # media was sitting right there in the library.
    item
    |> InboxItem.changeset(%{status: :imported, media_id: media.id, issue: nil})
    |> Repo.update()
  end
end
