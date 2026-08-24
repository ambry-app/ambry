defmodule Ambry.Inbox.Importer do
  @moduledoc """
  Turns a fully-resolved staged import into real library records.

  Import is the only thing that creates records — discovery, matching and the
  form only ever propose. It covers the whole entity graph in one
  transaction: book, authors, narrators, series, the recording and its
  direct-play tracks, so a half-imported item can't exist.

  It executes a draft and decides nothing: it refuses unless
  `Draft.resolved?/1` and then does exactly what the draft says. There are no
  fallbacks, since inventing a series number is the confidently-wrong data
  the inbox exists to prevent.

  Placement puts the files into a library root under the naming template, by
  the policy the draft settled, and refuses where a hardlink would cross a
  filesystem rather than silently copying.

  Provenance is written by construction: a provider value records that
  provider and stays unlocked, a typed value records `manual` and locks.
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
  alias Ambry.Inbox.Preflight
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
  alias Ambry.Wanted

  require Logger

  @doc """
  Imports an item, creating everything its draft implies.

  Returns `{:ok, media}`, or `{:error, reason}` — leaving the item untouched
  and the library unchanged.
  """
  def import_item(%InboxItem{status: :imported}), do: {:error, :already_imported}

  def import_item(%InboxItem{} = item) do
    item = Repo.preload(item, :source)

    # Files, then the draft, then placement: no amount of curation fixes a
    # vanished file, so reporting a decision on one sends them to the form
    # for nothing.
    with {:ok, files} <- audio_files(item),
         known = Preflight.check(item),
         {:ok, probes} <- probe_all(files),
         :ok <- resolved(item),
         {:ok, destination} <- destination(item),
         {:ok, outcome} <- create(item, files, probes, destination, known) do
      # Only now, with the records committed, is anything destroyed.
      finish(outcome, item)
      {:ok, outcome.media}
    end
  end

  # Everything that had to wait for the commit. None of it may fail the
  # import: the library holds the recording, and a job reported as failed is
  # a lie the operator acts on.
  defp finish(outcome, item) do
    log_finalize(Placement.finalize(outcome.placements), item)
    Placement.discard(outcome.vacated)
    retire(outcome)
    settle_watches(item, outcome.media)
    :ok
  end

  # The other end of the watch, keyed on the records the *draft* adopted and
  # not everything the matcher proposed: a candidate passed over is no
  # evidence. Like everything in `finish/2` it may not fail the import.
  defp settle_watches(%InboxItem{} = item, %Media.Media{} = media) do
    case adopted_refs(item) do
      [] ->
        :ok

      refs ->
        settled = Wanted.settle(refs, media)

        Enum.each(settled, fn watch ->
          Logger.info("Import satisfied a watch: #{watch.edition.title} (##{watch.id})")
        end)
    end
  rescue
    error ->
      Logger.warning("Could not settle watches for item #{item.id}: #{inspect(error)}")
      :ok
  end

  defp adopted_refs(%InboxItem{draft: %{recording: %{sources: sources}}}) when is_list(sources) do
    Enum.map(sources, &{&1.source, &1.id})
  end

  defp adopted_refs(_item), do: []

  defp retire(%{retired: nil}), do: :ok

  defp retire(%{retired: retired, placements: placements}) do
    # A retired name that placement just wrote to is the new file wearing it,
    # which a like-for-like replacement produces; deleting it would undo the
    # import that just succeeded.
    placed = Enum.map(placements, & &1.destination)

    {:ok, _job} =
      Media.delete_files_async(%{
        retired
        | files: retired.files -- placed,
          prune_from: retired.prune_from -- placed
      })

    :ok
  end

  # Claimed under a row lock before anything is created or any byte moves.
  # The status check at the door reads the *caller's* copy, so without the
  # lock two concurrent imports both walk through it and the loser rolls back
  # after its copy has landed.
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

  # **The pre-flight again, against the library as it is at the write.** The
  # click's pre-flight is a minute or more old by here, and a sibling that
  # committed inside that window created what this is about to create again.
  #
  # Refuses only on **new** findings: what the operator accepted at the button
  # is in both lists, and a relink sweep can only remove entries.
  #
  # **Not a guarantee.** At READ COMMITTED a peer's uncommitted rows are
  # invisible, so interleaved commits cannot see each other. This closes the
  # minute; closing the millisecond would mean serializing the file copies of
  # every import sharing an author. `Ambry.Inbox.Duplicates` reports the rest.
  defp no_new_collisions(%InboxItem{} = item, known) do
    case Preflight.check(item) -- known do
      [] -> :ok
      new -> {:error, {:collisions, new}}
    end
  end

  # The one branch in the module: a replacement repoints an existing recording
  # where an ordinary import creates one. Everything either side is the same
  # code, because it is the same import.
  defp create(%InboxItem{draft: draft} = item, files, probes, destination, known) do
    if Replacement.replacing?(draft.replacement) do
      replace(item, files, probes, destination, draft.replacement.media_id)
    else
      add(item, files, probes, destination, known)
    end
  end

  # The LAST thing inside the transaction. Fail earlier and no bytes moved;
  # fail at the commit and the worst case is a stray file the audit surfaces,
  # never a deleted source whose record did not survive.
  defp add(item, files, probes, destination, known) do
    Repo.transact(fn ->
      # People first, and for the whole draft at once: the same human can be
      # behind two credits, and each credit creating its own left a
      # self-narrated book with two Person rows of one name.
      with {:ok, item} <- claim(item),
           :ok <- no_new_collisions(item, known),
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

  # Better files for an audiobook the library already has. **Only the files
  # move**: the book, the credits, the chapters and every scalar stay as
  # curated, or a replacement is data loss wearing an upgrade's clothes.
  #
  # The outgoing files are read *first* (writing new tracks overwrites the
  # record of what this recording owns) and destroyed *last*, after the
  # commit, so a failure leaves the recording playing what it played before.
  defp replace(item, files, probes, destination, media_id) do
    Repo.transact(fn ->
      with {:ok, item} <- claim(item),
           {:ok, media} <- existing_recording(media_id),
           retired = Media.retired_files(media),
           {:ok, media} <- repoint(media, probes, destination),
           # Before the link, not after: `inbox_items_one_live_import_per_media`
           # is checked per statement and a partial unique index cannot be
           # deferred, so the previous claim has to be released before the
           # new one is made rather than the two overlapping for a statement.
           :ok <- supersede_previous(item, media),
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

  # The recording's files and nothing else. Track paths start as placeholders
  # in valid form (basenames under the destination root) because the path
  # CHECKs cannot wait for the commit; placement rewrites them in this same
  # transaction.
  #
  # The packaged artifacts go in the same statement as the tracks replacing
  # them, so the recording is playable at every instant a reader could see.
  # `source_path` and `source_files` clear there too: they describe a
  # transcode, and a recording served from tracks has none.
  defp repoint(media, probes, {root, _policy}) do
    %{
      library_root_id: root.id,
      source_path: nil,
      source_files: [],
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

  # Markers the recording does not have yet, never over ones it does: chapters
  # are curated data, and these files are a new rip of a recording somebody
  # has already been through.
  defp with_file_chapters(attrs, %{chapters: []}, probes) do
    case Scanner.chapters(probes) do
      {[], _source} -> attrs
      {chapters, source} -> Map.merge(attrs, %{chapters: chapters, chapter_marker_source: source})
    end
  end

  defp with_file_chapters(attrs, _has_chapters, _probes), do: attrs

  # A published recording stays published. A *legacy* one was published on the
  # strength of artifacts this replacement just retired, so where the fleet
  # cannot play tracks yet it goes back to pending and
  # `Ambry.Media.publish_pending_direct_play/0` releases it later.
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
    # Empty lists are omitted, not passed: `[]` counts as a change against an
    # unloaded assoc, and a changed list with no source stamps `manual`
    # provenance, so a book with no series would read "Series from you".
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

  # An identity's own changeset only casts its name, and creating one through
  # a Person cannot express "this pen name is two people", so the link rows go
  # in explicitly. A list longer than one is the composite-author case.
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

  # Every human the draft implies, created once each and returned by key. One
  # decision per human is the model's guarantee rather than something
  # reconstructed here: credits reference people by key, so there is nothing
  # to fold together.
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

  # A new person arrives complete, since one created bare is a trip to the
  # person form afterwards. A photo that will not fetch does not fail the
  # import: the credit is still correct without it.
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
  # The name is provenanced too, or it sees a changed field with no source and
  # records **manual, locked**, so every person the inbox creates claims to
  # have been typed by hand.
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
      do_create_media(book, probes, people, recording, group, root)
    end
  end

  # Resolved like a series link: `:link` joins the existing group, `:create`
  # mints one on the resolved book. Absent or tombstoned means no set.
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

  defp do_create_media(book, probes, people, recording, group, root) do
    {chapters, marker_source} = chapters(recording.chapters, probes)

    %{
      book_id: book.id,
      # In the destination root's coordinates from the start, because the
      # track path CHECKs cannot wait for the commit. Placeholders in valid
      # form that placement rewrites in this same transaction.
      # `source_path` / `source_files` stay empty: they are a transcode's
      # bookkeeping, and an import has no transcode.
      library_root_id: root.id,
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

  # A projection of the draft, since each decision knows where its value came
  # from: typed records `manual` and locks, accepted records the provider and
  # stays unlocked for a future refresh.
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

  # Where a structural list's members came from, when they share one, so the
  # edit form's list-level "from …" flag survives the import. Tombstoned rows
  # do not count: a removed proposal describes nothing that imported.
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

  # Published unless the switch says the fleet cannot play direct-play media
  # yet, in which case it waits in `pending`.
  #
  # The reload is load-bearing: `Media.changeset` reads tracks off the struct
  # to decide whether legacy paths are required, and an unloaded assoc reads
  # as "no tracks", demanding an mp4 path this recording will never have.
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

  # Every import places into a root; there is nowhere else Ambry serves from.
  # Read off the draft rather than re-derived from the source: any input may
  # feed any output, so the root and the policy are decisions, not properties
  # of where the files were found.
  defp destination(%InboxItem{draft: %{destination: %{root_id: root_id, policy: policy}}})
       when is_integer(root_id) and not is_nil(policy) do
    case Repo.get(Root, root_id) do
      %Root{} = root -> {:ok, {root, policy}}
      nil -> {:error, :no_library_root}
    end
  end

  defp destination(%InboxItem{}), do: {:error, :no_library_root}

  defp place({root, policy}, book, media, files, retiring) do
    # Forced: a freshly-created book carries `book_authors` with the nested
    # `author` unloaded, so without it every folder loses its author segment,
    # quietly, because the template collapses empty tokens.
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

  # A like-for-like replacement renders to the names it already occupies, and
  # placement never clobbers. Its own names are the one thing it may take, so
  # they are moved aside rather than overwritten, and put back on failure.
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

  # Recorded in `media_tracks` and only there. Not in `source_path` /
  # `source_files`, which state what a transcode consumed: an imported
  # recording has none, and saying otherwise answers "what was this made
  # from" with the recording's own files.
  defp record_placement(media, root, paths) do
    with {:ok, _tracks} <- repoint_tracks(media, root, paths) do
      media
      |> Ecto.Changeset.change(%{library_root_id: root.id})
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

  # A curated chapter list lands verbatim, hand-nudged times included. Safe
  # against the re-probe below because a file change flips the draft stale,
  # and import refuses a stale draft. Uncurated chapters re-derive.
  defp chapters(%Chapters{curated: true} = decision, _probes) do
    # plain maps, like the scanner's own rows — `cast_embed` refuses structs
    rows = Enum.map(decision.chapters, &Map.take(&1, [:time, :title, :title_source]))
    {rows, decision.chapter_marker_source}
  end

  defp chapters(_decision, probes), do: Scanner.chapters(probes)

  # Absolute disk paths in the order discovery recorded them, which is natural
  # sort and therefore the play order the form showed.
  defp audio_files(%InboxItem{files: []}), do: {:error, :no_audio_files}
  defp audio_files(%InboxItem{} = item), do: {:ok, InboxItem.disk_files(item)}

  # Re-probed rather than trusted: one ffprobe per file buys current track
  # data, and a file that vanished since discovery fails the import instead of
  # creating a recording that points at nothing.
  defp probe_all(files) do
    case Scanner.probe_all(files) do
      {:ok, probes} -> {:ok, probes}
      {:error, reason} -> {:error, {:unreadable, reason}}
    end
  end

  defp link(item, media) do
    # `issue: nil` because succeeding is what resolves a failed attempt's
    # reason; left in place it sits in red on a row whose media is in the
    # library. `item` is the row `claim/1` locked, so it cannot be stale, but
    # it still bumps the version, which tells an open form what happened.
    item
    |> InboxItem.changeset(%{status: :imported, media_id: media.id, issue: nil})
    |> InboxItem.versioned()
    |> Repo.update()
  end

  # The item this one took over from stops being the recording's import. Runs
  # after `link/2`, so the row it must not touch is the one that now holds
  # this media id.
  #
  # `updated_at` is deliberately left alone: it is the moment the superseded
  # item was imported, which is the row's date and the imported tab's sort.
  # `Repo.update_all` not bumping it is relied on rather than an omission.
  #
  # Ordinarily one row, zero when the recording came from outside the inbox.
  defp supersede_previous(%InboxItem{id: id}, %Media.Media{id: media_id}) do
    import Ecto.Query, only: [where: 3]

    InboxItem
    |> where([i], i.media_id == ^media_id and i.id != ^id)
    |> where([i], i.status == :imported and is_nil(i.superseded_by_id))
    |> Repo.update_all(set: [superseded_by_id: id])

    :ok
  end
end
