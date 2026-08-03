defmodule Ambry.Inbox.Approval do
  @moduledoc """
  Turns a curated inbox item into real library records.

  Approval is the only thing that creates records — discovery and matching
  only ever propose. It covers the whole entity graph in one transaction:
  book, authors, narrators, series, the recording and its direct-play tracks.
  Either all of it lands or none of it does, so a half-approved item can't
  exist.

  ## Custody

  Recordings created here are **external**: the files are referenced exactly
  where they lie and Ambry never moves, copies, renames or deletes them.
  Removing such a recording later deletes records only. Hardlinking messy
  sources into a managed library tree is the rest of 3a; external custody is
  both the honest default for a watched folder and the only thing that can
  work against a read-only mount.

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
  alias Ambry.Media
  alias Ambry.Media.Scanner
  alias Ambry.People
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.Repo

  @doc """
  Approves an item, creating everything it implies.

  Returns `{:ok, media}`, or `{:error, reason}` — leaving the item untouched
  and the library unchanged.
  """
  def approve(%InboxItem{status: :approved}), do: {:error, :already_approved}

  def approve(%InboxItem{} = item) do
    with {:ok, file} <- single_file(item),
         {:ok, probe} <- probe(file) do
      Repo.transact(fn ->
        with {:ok, book} <- resolve_book(item),
             {:ok, media} <- create_media(item, book, probe),
             {:ok, _item} <- link(item, media) do
          {:ok, media}
        end
      end)
    end
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
