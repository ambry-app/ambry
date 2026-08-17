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

  ## Placement

  Every import places its files into a library root under the naming
  template, by the policy the draft settled — hardlink, symlink, copy or
  move. The original is untouched by construction for the first three and
  deliberately gone for the last; there is no import that leaves the
  library referencing a path outside a root.

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
  alias Ambry.Inbox.Draft.Chapters
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library
  alias Ambry.Library.NamingTemplate
  alias Ambry.Library.Placement
  alias Ambry.Library.Root
  alias Ambry.Media
  alias Ambry.Media.RecordingGroup
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
    # order is the order the operator can act on them: a vanished file is not
    # something any amount of curation fixes, so reporting an unresolved
    # decision on one would send them to the form to fix something the form
    # can't fix.
    with {:ok, files} <- audio_files(item),
         {:ok, probes} <- probe_all(files),
         :ok <- resolved(item),
         {:ok, destination} <- destination(item),
         {:ok, outcome} <- create(item, files, probes, destination) do
      # Only now, with the records committed, is anything destroyed: a moved
      # file's source, the names a replacement moved aside, and the files the
      # recording it replaced was served from.
      finish(outcome, item)
      {:ok, outcome.media}
    end
  end

  # Everything that had to wait for the commit. None of it may fail the
  # import — the library holds the recording, and a job reported as failed is
  # a lie the operator acts on — so each part says so where it happens.
  defp finish(outcome, item) do
    log_finalize(Placement.finalize(outcome.placements), item)
    Placement.discard(outcome.vacated)
    retire(outcome)
    :ok
  end

  defp retire(%{retired: nil}), do: :ok

  defp retire(%{retired: retired, placements: placements}) do
    # A retired name that placement just wrote to is the *new* file wearing
    # the old name, which is exactly what a like-for-like replacement
    # produces. Deleting it would undo the import that just succeeded.
    placed = Enum.map(placements, & &1.destination)

    {:ok, _job} =
      Media.delete_files_async(%{
        retired
        | files: retired.files -- placed,
          prune_from: retired.prune_from -- placed
      })

    :ok
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

  # The one branch in the whole module, and it is the smallest one there is:
  # a replacement repoints an existing recording where an ordinary import
  # creates one. Everything either side of that — the claim, the item link,
  # placement, the finish — is the same code, because it is the same import.
  defp create(%InboxItem{draft: draft} = item, files, probes, destination) do
    if Replacement.replacing?(draft.replacement) do
      replace(item, files, probes, destination, draft.replacement.media_id)
    else
      add(item, files, probes, destination)
    end
  end

  # Placement is deliberately the LAST thing inside the transaction, with
  # nothing but the commit after it. Fail earlier and no bytes have moved;
  # fail at the commit and the worst case is a stray file in the library,
  # which the audit tooling surfaces — never a file whose source was already
  # deleted and whose record didn't survive.
  defp add(item, files, probes, destination) do
    Repo.transact(fn ->
      # People first, and for the whole draft at once: the same human can be
      # behind two credits, and each credit creating its own left a
      # self-narrated book with two Person rows of one name.
      with {:ok, item} <- claim(item),
           {:ok, people} <- resolve_people(item.draft),
           {:ok, book} <- resolve_book(item.draft.work, people),
           {:ok, media} <- create_media(item, book, probes, people, destination),
           {:ok, _item} <- link(item, media),
           {:ok, media, placements, vacated} <- place(destination, book, media, files, []),
           {:ok, media} <- publish(media) do
        {:ok, %{media: media, placements: placements, vacated: vacated, retired: nil}}
      end
    end)
  end

  # Better files for an audiobook the library already has.
  #
  # What it is *not* allowed to do is as much of the point as what it does:
  # the book, the credits, the chapters and every scalar the recording
  # carries are its own, curated by whoever curated them, and a replacement
  # that reseeded any of it from tonight's providers would be a data loss
  # wearing an upgrade's clothes. Only the files move.
  #
  # The old files are read *first* — `media_tracks` is the record of what
  # this recording owns on disk, and once new tracks are written the old ones
  # are gone — and destroyed *last*, after the commit, so a failure anywhere
  # in here leaves the recording playing exactly what it played before.
  defp replace(item, files, probes, destination, media_id) do
    Repo.transact(fn ->
      with {:ok, item} <- claim(item),
           {:ok, media} <- existing_recording(media_id),
           retired = Media.retired_files(media),
           {:ok, media} <- repoint(media, item, probes, destination),
           {:ok, _item} <- link(item, media),
           {:ok, media, placements, vacated} <-
             place(destination, media.book, media, files, retired.files),
           {:ok, media} <- republish(media) do
        {:ok, %{media: media, placements: placements, vacated: vacated, retired: retired}}
      end
    end)
  end

  defp existing_recording(media_id) do
    case Repo.get(Media.Media, media_id) do
      nil -> {:error, :no_such_recording}
      media -> {:ok, Repo.preload(media, [:media_tracks, :book, :recording_group])}
    end
  end

  # The recording's files, and nothing else about it. The paths are
  # placeholders in valid form — basenames under the destination root — for
  # the same reason `do_create_media/7` writes them that way: the path CHECKs
  # cannot wait for the commit, and placement rewrites them to the real
  # relative paths inside this same transaction.
  #
  # The packaged artifacts go in the same statement as the tracks that
  # replace them, which is what keeps the recording playable at every instant
  # a reader could see: a recording with neither is one `maybe_validate_paths`
  # refuses, and rightly.
  defp repoint(media, item, probes, {root, _policy}) do
    %{
      library_root_id: root.id,
      source_path: Path.basename(item.path),
      source_files: Enum.map(item.files, &Path.basename/1),
      duration: Scanner.total_duration(probes),
      mp4_path: nil,
      mpd_path: nil,
      hls_path: nil,
      media_tracks:
        probes
        |> Scanner.track_attrs()
        |> Enum.map(&%{&1 | path: Path.basename(&1.path)})
        |> Enum.map(&Map.put(&1, :library_root_id, root.id))
    }
    |> with_file_chapters(media, probes)
    |> then(&Media.update_media(media, &1))
  end

  # Markers the recording doesn't have yet, and never over ones it does — the
  # rule `Ambry.Media.Scanner` has always followed for a rescan, and for the
  # same reason: chapters are curated data and these files are a new rip of a
  # recording somebody has already been through.
  defp with_file_chapters(attrs, %{chapters: []}, probes) do
    case Scanner.chapters(probes) do
      {[], _source} -> attrs
      {chapters, source} -> Map.merge(attrs, %{chapters: chapters, chapter_marker_source: source})
    end
  end

  defp with_file_chapters(attrs, _has_chapters, _probes), do: attrs

  # A published recording stays published: replacing its files doesn't
  # re-publish anything. A *legacy* one, though, was published on the
  # strength of the artifacts this replacement just retired — so where the
  # fleet can't play tracks yet it goes back to pending, and
  # `Ambry.Media.publish_pending_direct_play/0` releases it with the rest
  # when the switch is turned on.
  defp republish(%{status: :ready} = media) do
    if Settings.direct_play_publishing?() do
      {:ok, media}
    else
      Media.update_media(media, %{status: :pending})
    end
  end

  defp republish(media), do: {:ok, media}

  ## the work

  # A linked book is used exactly as it is — an import never edits it.
  defp resolve_book(%{mode: :link, book_id: book_id}, _people) do
    case Repo.get(Book, book_id) do
      nil -> {:error, :book_not_found}
      book -> {:ok, book}
    end
  end

  defp resolve_book(%{mode: :create} = work, people) do
    # Empty lists are omitted, not passed: on a new record `[]` still
    # counts as a change against the unloaded assoc, and a changed list
    # with no source stamps `manual` provenance — which is how every
    # zero-series import wore "Series from you" on the edit form.
    %{
      title: Field.value(work.title),
      published: Field.date(work.published),
      published_format: Field.format_atom(work.published, :full)
    }
    |> put_non_empty(:book_authors, author_params(work.authors, people))
    |> put_non_empty(:series_books, series_params(work.series))
    |> Books.create_book(
      provenance:
        %{
          "title" => work.title,
          "published" => work.published,
          "published_format" => work.published
        }
        |> provenance()
        |> put_list_provenance("book_authors", work.authors)
        |> put_list_provenance("series_books", work.series)
    )
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

  defp create_media(item, book, probes, people, {root, _policy}) do
    recording = item.draft.recording

    with {:ok, group} <- resolve_group(recording.recording_group, book) do
      do_create_media(item, book, probes, people, recording, group, root)
    end
  end

  # The draft's group link, resolved like a series link: `:link` joins the
  # existing group, `:create` mints one on the resolved book, carrying the
  # set-level facts the operator settled. Absent or tombstoned means not
  # part of any set.
  defp resolve_group(nil, _book), do: {:ok, nil}
  defp resolve_group(%GroupLink{removed: true}, _book), do: {:ok, nil}

  defp resolve_group(%GroupLink{mode: :link, recording_group_id: id}, _book),
    do: {:ok, Repo.get!(RecordingGroup, id)}

  defp resolve_group(%GroupLink{mode: :create} = link, book),
    do:
      Media.create_recording_group(%{
        name: link.name,
        book_id: book.id,
        parts_total: link.parts_total
      })

  defp do_create_media(item, book, probes, people, recording, group, root) do
    {chapters, marker_source} = chapters(recording.chapters, probes)

    %{
      book_id: book.id,
      # Created in the destination root's coordinates from the start: the
      # path columns are CHECK-constrained to hold a resolvable stored form,
      # and a CHECK cannot wait for the commit. These are placeholders in
      # valid form — basenames under the right root — that placement
      # rewrites to the real relative paths inside this same transaction.
      library_root_id: root.id,
      source_path: Path.basename(item.path),
      source_files: Enum.map(item.files, &Path.basename/1),
      status: :pending,
      # The recording's settled place in its part set, if any.
      part_number: part_number(recording.recording_group),
      recording_group_id: group && group.id,
      duration: Scanner.total_duration(probes),
      chapters: chapters,
      chapter_marker_source: marker_source,
      media_tracks:
        probes
        |> Scanner.track_attrs()
        |> Enum.map(&%{&1 | path: Path.basename(&1.path)})
        |> Enum.map(&Map.put(&1, :library_root_id, root.id)),
      title: Field.value(recording.title),
      published: Field.date(recording.published),
      published_format: Field.format_atom(recording.published, :full),
      publisher: Field.value(recording.publisher),
      description: Field.value(recording.description),
      image_path: cover(recording.cover)
    }
    # omitted when empty, same reason as `resolve_book/2`'s lists — and a
    # full-cast recording crediting nobody is legal, not a gap
    |> put_non_empty(:media_narrators, narrator_params(recording.narrators, people))
    |> Media.create_media(
      provenance:
        %{
          "title" => recording.title,
          "published" => recording.published,
          "published_format" => recording.published,
          "publisher" => recording.publisher,
          "description" => recording.description,
          "image_path" => recording.cover
        }
        |> provenance()
        |> put_list_provenance("media_narrators", recording.narrators)
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

  ## provenance

  # Each decision already knows where its value came from, so the provenance
  # map is a projection of the draft rather than anything to collect
  # separately. A field the operator typed records `manual` and locks; an
  # accepted provider value records that provider and stays unlocked, so a
  # future refresh may still update it.
  defp provenance(fields) do
    fields
    |> Enum.flat_map(fn
      {_name, nil} ->
        []

      {_name, %Field{source: nil}} ->
        []

      {_name, %Field{source: "manual"}} ->
        []

      {name, %Field{source: source, record: nil}} ->
        [{name, source}]

      {name, %Field{source: source, record: record}} ->
        [{name, %{"source" => source, "record" => record}}]
    end)
    |> Map.new()
  end

  # The list-level source: where a structural list's members came from, when
  # they share one. Credits carry their own source; the list records the
  # first provider-ish one, so the edit form's "Authors — from rreading-glasses"
  # flag survives the import the way scalar flags always did. Tombstoned rows
  # don't count: a removed proposal's source describes nothing that imported.
  defp list_provenance(entries) do
    entries
    |> Enum.reject(& &1.removed)
    |> Enum.map(& &1.source)
    |> Enum.find(&(is_binary(&1) and &1 not in ["manual"]))
  end

  defp put_list_provenance(sources, name, entries) do
    case list_provenance(List.wrap(entries)) do
      nil -> sources
      source -> Map.put(sources, name, source)
    end
  end

  defp put_non_empty(params, _key, []), do: params
  defp put_non_empty(params, key, list), do: Map.put(params, key, list)

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

  # Where import puts the bytes. Every import places into a root — there is
  # no other place Ambry serves from. Read off the draft rather than
  # re-derived from the source: any input may feed any output, so which root
  # this import goes to and how the files come in are decisions the operator
  # made (or that resolved silently because there was only one root and the
  # source carried a policy), not properties of where the files were found.
  defp destination(%InboxItem{draft: %{destination: %{root_id: root_id, policy: policy}}})
       when is_integer(root_id) and not is_nil(policy) do
    case Repo.get(Root, root_id) do
      %Root{} = root -> {:ok, {root, policy}}
      nil -> {:error, :no_library_root}
    end
  end

  defp destination(%InboxItem{}), do: {:error, :no_library_root}

  defp place({root, policy}, book, media, files, retiring) do
    # Forced: a freshly-created book carries its `book_authors` as insert
    # results with the nested `author` unloaded, and a reused one carries
    # nothing at all. Without this every folder silently loses its author
    # segment — the template collapses empty tokens, so it fails quietly
    # rather than raising.
    book = Repo.preload(book, [{:book_authors, :author}, {:series_books, :series}], force: true)
    media = Repo.preload(media, [{:media_narrators, :narrator}, :recording_group], force: true)

    values = Books.naming_values(book, media)

    with {:ok, folder} <- NamingTemplate.render(Settings.library_naming_template(), values),
         {:ok, filenames} <- NamingTemplate.filenames(values, files, filename_recording(media)),
         paths = Enum.map(filenames, &Path.join([root.path, folder, &1])),
         {:ok, vacated} <- Placement.vacate(Enum.filter(paths, &(&1 in retiring))),
         {:ok, placements} <- place_all(Enum.zip(files, paths), policy, vacated),
         {:ok, media} <- record_placement(media, root, paths) do
      {:ok, media, placements, vacated}
    end
  end

  # A recording rendering to the same names it already occupies is what a
  # like-for-like replacement *is* — same book, same recording, so the same
  # token and the same filenames — and placement never clobbers. Its own
  # names are the one thing it may take, so they're moved aside rather than
  # overwritten, and put back if the placement then fails.
  defp place_all(pairs, policy, vacated) do
    case Placement.place_all(pairs, policy) do
      {:ok, placements} ->
        {:ok, placements}

      {:error, reason} ->
        Placement.restore(vacated)
        {:error, reason}
    end
  end

  # What distinguishes this recording from the others in its book folder: the
  # part label a human reads, and the token that guarantees it regardless.
  # Placement happens after the media is inserted, so the id exists.
  defp filename_recording(media) do
    %{part: filename_part(media), token: Media.filename_token(media)}
  end

  # Two parts of one set are two separate imports into the same book folder;
  # the suffix is what says which is which. Total and wording are the group's
  # facts.
  defp filename_part(%{part_number: nil}), do: nil

  defp filename_part(%{part_number: number, recording_group: group}) do
    %{number: number, total: group && group.parts_total, word: group && group.part_word}
  end

  # A tombstoned link imports groupless — removal is an answer.
  defp part_number(%GroupLink{removed: false, part_number: number}), do: number
  defp part_number(_absent_or_removed), do: nil

  # The recording now points at the library copies and Ambry owns those
  # names. `source_path` is the folder those copies share, which for a
  # multi-file recording is the subfolder of its own that placement gave it,
  # not the book folder it sits in.
  defp record_placement(media, root, paths) do
    with {:ok, _tracks} <- repoint_tracks(media, root, paths) do
      media
      |> Ecto.Changeset.change(%{
        library_root_id: root.id,
        source_path: relativize!(root, paths |> hd() |> Path.dirname()),
        source_files: Enum.map(paths, &relativize!(root, &1))
      })
      |> Repo.update()
    end
  end

  # Placement just wrote these under the root, so being outside it is a bug
  # worth crashing on rather than recording.
  defp relativize!(root, absolute) do
    {:ok, relative} = Library.relativize(root, absolute)
    relative
  end

  # Zipped by position, and the positions are the same order everywhere: the
  # probes were taken in it, the tracks were written in it, and the
  # destination names were rendered from it.
  defp repoint_tracks(%{media_tracks: [_ | _] = tracks}, root, paths) do
    tracks
    |> Enum.sort_by(& &1.index)
    |> Enum.zip(paths)
    |> Enum.reduce_while({:ok, []}, fn {track, path}, {:ok, acc} ->
      track
      |> Ecto.Changeset.change(%{path: relativize!(root, path), library_root_id: root.id})
      |> Repo.update()
      |> case do
        {:ok, track} -> {:cont, {:ok, [track | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp repoint_tracks(_no_tracks, _root, _paths), do: {:error, :no_tracks}

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

  # A curated chapter list is the operator's answer and lands verbatim —
  # including any hand-nudged times. That is safe against the re-probe below
  # because a file change flips the draft stale, and a stale draft is
  # unresolved: import refuses before it gets here. Uncurated chapters
  # re-derive from the fresh probe, exactly what the seeder showed.
  defp chapters(%Chapters{curated: true} = decision, _probes) do
    # plain maps, like the scanner's own rows — `cast_embed` refuses structs
    rows = Enum.map(decision.chapters, &Map.take(&1, [:time, :title, :title_source]))
    {rows, decision.chapter_marker_source}
  end

  defp chapters(_decision, probes), do: Scanner.chapters(probes)

  # An item's files as absolute disk paths, in the order discovery recorded
  # them — which is natural sort, and therefore the play order the operator
  # saw listed on the form. A release the operator has decided is really two
  # books is split into separate items first; this is the one they've said
  # is one recording.
  defp audio_files(%InboxItem{files: []}), do: {:error, :no_audio_files}
  defp audio_files(%InboxItem{} = item), do: {:ok, InboxItem.disk_files(item)}

  # Re-probed rather than trusting what discovery recorded: it costs one
  # ffprobe per file and buys current track data, plus a file that vanished
  # between discovery and import failing the import instead of creating a
  # recording that points at nothing.
  defp probe_all(files) do
    case Scanner.probe_all(files) do
      {:ok, probes} -> {:ok, probes}
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
