defmodule Ambry.Inbox.Approval do
  @moduledoc """
  Turns a curated inbox item into real library records.

  Approval is the only thing that creates records — discovery and matching
  only ever propose. It covers the whole entity graph in one transaction:
  book, authors, narrators, series, the recording and its direct-play tracks.
  Either all of it lands or none of it does, so a half-approved item can't
  exist.

  ## Custody

  Where an item came from decides what happens to its bytes:

    * from a **downloads** location, the file is brought into that location's
      library root under the naming template — hardlinked, copied or moved
      per the location's policy — and the recording becomes **managed**.
      Ambry owns those bytes and may reorganize or delete them.
    * from an **external collection**, or from an item with no location at
      all, the file is referenced exactly where it lies and the recording is
      **external**. Ambry never moves, copies, renames or deletes it, and
      removing the recording later deletes records only. This is also the
      only thing that can work against a read-only mount.

  A hardlink cannot cross a filesystem, and here the downloads folder and the
  library can easily be on different NAS boxes. Approval **refuses** in that
  case rather than falling back to a copy: a silent copy is the storage
  doubling this whole phase exists to eliminate, and the operator would have
  no way to know it happened.

  ## Publishing

  Approval does not publish. The recording is created `pending`, so clients
  don't see it until the direct-play switch is on and it's marked ready —
  the client-first rollout order the whole of Phase 2 is built around.

  ## Re-probing

  The files are probed again here rather than trusting what discovery
  recorded. It costs one ffprobe and buys two things: the track data is
  current at the moment it's written, and a file that vanished between
  discovery and approval fails the approval instead of creating a recording
  that points at nothing.
  """

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library
  alias Ambry.Library.Location
  alias Ambry.Library.NamingTemplate
  alias Ambry.Library.Placement
  alias Ambry.Media
  alias Ambry.Media.Scanner
  alias Ambry.People
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.Repo
  alias Ambry.Settings

  require Logger

  @doc """
  Approves an item, creating everything it implies.

  Returns `{:ok, media}`, or `{:error, reason}` — leaving the item untouched
  and the library unchanged.
  """
  def approve(%InboxItem{status: :approved}), do: {:error, :already_approved}

  def approve(%InboxItem{} = item) do
    item = Repo.preload(item, :location)

    with {:ok, file} <- single_file(item),
         {:ok, probe} <- probe(file),
         {:ok, destination} <- destination(item),
         {:ok, {media, placement}} <- create(item, file, probe, destination) do
      # Only now, with the records committed, is it safe to remove a moved
      # file's source.
      log_finalize(Placement.finalize(placement), item)
      {:ok, media}
    end
  end

  # Placement is deliberately the LAST thing inside the transaction, with
  # nothing but the commit after it. Fail earlier and no bytes have moved;
  # fail at the commit and the worst case is a stray file in the library,
  # which the audit tooling surfaces — never a file whose source was already
  # deleted and whose record didn't survive.
  defp create(item, file, probe, destination) do
    Repo.transact(fn ->
      with {:ok, book} <- resolve_book(item),
           {:ok, media} <- create_media(item, book, probe),
           {:ok, _item} <- link(item, media),
           {:ok, media, placement} <- place(destination, book, media, file),
           {:ok, media} <- publish(media) do
        {:ok, {media, placement}}
      end
    end)
  end

  # An approved recording is finished, so it's published — unless the switch
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

  # What approval should do with the bytes, decided by where the item came
  # from. Only a downloads folder imports; an external collection is adopted
  # exactly where it lies (that is the entire promise of external custody),
  # and a file already sitting in a library root is already home.
  defp destination(%InboxItem{location: %Location{kind: :downloads} = location}) do
    with {:ok, root} <- Library.target_root(location) do
      {:ok, {root, location.import_policy}}
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
         {:ok, filename} <- NamingTemplate.filename(values, file),
         path = Path.join([root.path, folder, filename]),
         {:ok, placement} <- Placement.place(file, path, policy),
         {:ok, media} <- adopt_managed(media, path) do
      {:ok, media, placement}
    end
  end

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
      "Approved #{item.path} but couldn't remove the source: #{inspect(reason)}"
    end)
  end

  # Direct-play v1 is single-file, and a recording whose tracks can't be
  # described has no business in the library.
  defp single_file(%InboxItem{files: [file]}), do: {:ok, file}
  defp single_file(%InboxItem{files: []}), do: {:error, :no_audio_files}
  defp single_file(%InboxItem{}), do: {:error, :multi_file_unsupported}

  defp probe(file) do
    case Scanner.probe_file(file, single_file: true) do
      {:ok, probe} -> {:ok, probe}
      {:error, reason} -> {:error, {:unreadable, reason}}
    end
  end

  # An existing Book is always preferred over a new one: reusing the work is
  # what keeps a second recording of it from splitting the library in two.
  defp resolve_book(%InboxItem{} = item) do
    case selected(item, "work") do
      %{"source" => "local", "id" => id} -> fetch_book(id)
      candidate -> create_book(item, candidate)
    end
  end

  defp fetch_book(id) do
    case Repo.get(Book, id) do
      nil -> {:error, :book_not_found}
      book -> {:ok, book}
    end
  end

  defp create_book(item, candidate) do
    hints = hints(item)
    title = presence(candidate["title"]) || hints["title"]
    {published, format} = published(candidate, hints)

    cond do
      is_nil(title) ->
        {:error, :no_title}

      # A work has to have a publication date, and the inbox has no business
      # inventing one — today's date would be worse than no import. Matching
      # a work supplies it; so does tagging the file.
      is_nil(published) ->
        {:error, :no_published_date}

      true ->
        Books.create_book(%{
          title: title,
          published: published,
          published_format: format,
          book_authors: author_params(candidate, hints),
          series_books: series_params(candidate, hints)
        })
    end
  end

  defp published(candidate, hints) do
    case date(candidate["published"]) do
      nil -> {date(hints["published"]), format(hints["published_format"]) || :year}
      date -> {date, format(candidate["published_format"]) || :full}
    end
  end

  defp format(format) when format in ["full", "year_month", "year"],
    do: String.to_existing_atom(format)

  defp format(format) when format in [:full, :year_month, :year], do: format
  defp format(_other), do: nil

  defp author_params(candidate, hints) do
    names = names(candidate["authors"]) || names(hints["authors"]) || []

    Enum.map(names, fn name ->
      {:ok, author} = find_or_create_author(name)
      %{author_id: author.id}
    end)
  end

  defp series_params(candidate, hints) do
    case candidate["series"] |> List.wrap() |> List.first() |> presence() ||
           presence(hints["series"]) do
      nil ->
        []

      name ->
        {:ok, series} = find_or_create_series(name)
        [%{series_id: series.id, book_number: decimal(hints["series_number"]) || Decimal.new(1)}]
    end
  end

  defp create_media(item, book, probe) do
    candidate = selected(item, "recording") || %{}
    hints = hints(item)

    Media.create_media(%{
      book_id: book.id,
      # external custody: referenced where they lie, never touched
      custody: :external,
      source_path: item.path,
      source_files: item.files,
      status: :pending,
      duration: probe.duration,
      chapters: chapter_params(probe),
      media_narrators: narrator_params(candidate, hints),
      media_tracks: [track_params(probe)],
      published: date(candidate["published"]),
      publisher: presence(candidate["publisher"]) || presence(hints["publisher"]),
      description: presence(candidate["description"]) || presence(hints["description"])
    })
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

  defp chapter_params(%{chapters: chapters}), do: chapters

  defp narrator_params(candidate, hints) do
    names = names(candidate["narrators"]) || names(hints["narrators"]) || []

    Enum.map(names, fn name ->
      {:ok, narrator} = find_or_create_narrator(name)
      %{narrator_id: narrator.id}
    end)
  end

  # Attach-or-create, by exact name, case-insensitively. A brand-new credit
  # brings a Person into being with it, because an Author or Narrator is an
  # identity *of* somebody — there's no such thing as a free-floating one.
  defp find_or_create_author(name) do
    case Repo.one(from a in Author, where: fragment("lower(?)", a.name) == ^String.downcase(name)) do
      %Author{} = author ->
        {:ok, author}

      nil ->
        with {:ok, person} <-
               People.create_person(%{name: name, author_people: [%{author: %{name: name}}]}) do
          person = Repo.preload(person, :authors)
          {:ok, hd(person.authors)}
        end
    end
  end

  defp find_or_create_narrator(name) do
    query = from n in Narrator, where: fragment("lower(?)", n.name) == ^String.downcase(name)

    case Repo.one(query) do
      %Narrator{} = narrator ->
        {:ok, narrator}

      nil ->
        with {:ok, person} <- People.create_person(%{name: name, narrators: [%{name: name}]}) do
          person = Repo.preload(person, :narrators)
          {:ok, hd(person.narrators)}
        end
    end
  end

  defp find_or_create_series(name) do
    query = from s in Series, where: fragment("lower(?)", s.name) == ^String.downcase(name)

    case Repo.one(query) do
      %Series{} = series -> {:ok, series}
      nil -> Books.create_series(%{name: name})
    end
  end

  defp link(item, media) do
    item
    |> InboxItem.changeset(%{status: :approved, media_id: media.id})
    |> Repo.update()
  end

  defp selected(%InboxItem{matches: matches}, level) when is_map(matches) do
    candidates = get_in(matches, [level, "candidates"]) || []
    selection = get_in(matches, [level, "selected"])

    Enum.find(candidates, List.first(candidates), fn candidate ->
      (selection && candidate["source"] == selection["source"]) and
        candidate["id"] == selection["id"]
    end)
  end

  defp selected(_item, _level), do: nil

  # One hint builder, shared with matching, so approving an item that was
  # never matched still knows what its files say it is.
  defp hints(%InboxItem{} = item) do
    parsed = AutoMatch.hints(item)
    tags = item.tags || %{}

    %{
      "title" => parsed.title,
      "authors" => names(tags["authors"]) || names(parsed.author) || [],
      "narrators" => names(tags["narrators"]) || names(parsed.narrator) || [],
      "series" => parsed.series,
      "series_number" => tags["series_number"],
      "published" => tags["published"],
      "published_format" => tags["published_format"],
      "publisher" => tags["publisher"],
      "description" => tags["description"]
    }
  end

  defp names(nil), do: nil
  defp names([]), do: nil
  defp names(names) when is_list(names), do: Enum.filter(names, &presence/1)
  defp names(name) when is_binary(name), do: [name]

  defp date(nil), do: nil

  defp date(string) when is_binary(string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date(%Date{} = date), do: date
  defp date(_other), do: nil

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = decimal), do: decimal

  defp decimal(string) when is_binary(string) do
    case Decimal.parse(string) do
      {decimal, ""} -> decimal
      _unparseable -> nil
    end
  end

  defp decimal(_other), do: nil

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(other), do: other
end
