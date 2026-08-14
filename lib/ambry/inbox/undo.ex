defmodule Ambry.Inbox.Undo do
  @moduledoc """
  Puts an imported item back the way it was, for development only.

  ## Why this exists at all

  The import form is designed by running real releases through it, and the
  interesting releases are the awkward ones — a pen name, a composite author,
  a set of three parts. Each of those can only be imported once, so every
  round of "that reads wrong, try again" cost a hand-written cleanup of a
  Media, a Book, two identities and however many People, in the right order,
  before the same release could be run again. The loop the whole staged form
  exists to support was the one thing the system made expensive.

  ## What it does, and what it deliberately won't

  Undo deletes the records this import created and flips the item back to
  pending with its draft intact, so the next run starts from the same
  decisions rather than from a fresh match.

  **Only what this import created.** The draft is the record of that: a
  `:link` decision reused something that was already there and is never
  touched, a `:create` decision made something new. Anything created here but
  since referenced by another recording — a book with a second edition, a
  narrator who has read something else — is kept, and named in the summary.
  Nothing about undoing one import may damage another.

  **Only when the source still exists.** Placement with a `move` policy is the
  case that makes this dangerous: the library copy is the only copy, and
  deleting it is not an undo, it is a loss. So the files the item was
  discovered as are checked first, and a release whose source is gone is
  refused with `:source_files_missing` rather than half-undone.

  **Dev only.** Gated on `:allow_undo_import`, which dev and test config set
  and no other config does, so on a production build every call returns
  `{:error, :undo_unavailable}` — the button not rendering is the explanation,
  this is the enforcement. `Ambry.Inbox.undo_available?/0` is what the admin
  form asks before offering it.
  """

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.InboxItem
  alias Ambry.Media
  alias Ambry.People
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  @doc "Whether this build has the undo at all."
  def available?, do: Application.get_env(:ambry, :allow_undo_import, false)

  @doc """
  Deletes what an import created and returns the item to the queue.

  Returns `{:ok, summary}` where the summary says what went and what was kept,
  which is the interesting half: "the book stayed, another recording uses it"
  is the answer to a question the operator would otherwise ask by hand.
  """
  def undo_import(item, opts \\ [])

  def undo_import(%InboxItem{status: status}, _opts) when status != :imported,
    do: {:error, :not_imported}

  def undo_import(%InboxItem{} = item, _opts) do
    with :ok <- allowed(),
         :ok <- source_intact(item) do
      draft = item.draft
      media = item.media_id && Repo.get(Media.Media, item.media_id)

      # Records first, then the item: an item back in the queue while its
      # media still exists is the one state that would let the operator
      # import a second copy of what is already there.
      summary =
        %{deleted: [], kept: []}
        |> drop_media(media)
        |> drop_book(draft, media)
        |> drop_series(draft)
        |> drop_people(draft)
        |> drop_identities(draft)

      with {:ok, item} <- requeue(item) do
        # Every other queued item that might have been about to reuse one of
        # these records has to be re-derived, exactly as it was when the
        # import created them.
        Ambry.Inbox.refresh_siblings(item)

        {:ok,
         %{item: item, deleted: Enum.reverse(summary.deleted), kept: Enum.reverse(summary.kept)}}
      end
    end
  end

  defp allowed do
    if available?(), do: :ok, else: {:error, :undo_unavailable}
  end

  # The check that makes this safe to offer. A `move` policy leaves the
  # library copy as the only copy, and `Media.delete_media/1` deletes a
  # recording's files — so without the source on disk, "undo" would delete
  # the release.
  defp source_intact(%InboxItem{files: []}), do: :ok

  defp source_intact(%InboxItem{} = item) do
    files = item |> Repo.preload(:source) |> InboxItem.disk_files()

    if Enum.all?(files, &File.exists?/1), do: :ok, else: {:error, :source_files_missing}
  end

  ## the records

  defp drop_media(summary, nil), do: note(summary, :kept, "no audiobook: the item had none")

  defp drop_media(summary, %Media.Media{} = media) do
    # The recording's library copies go with it. The originals they were
    # placed from are untouched by construction — which is exactly why
    # `source_intact/1` refused already if a move made the library copy the
    # only one.
    case Media.delete_media(media) do
      {:ok, _media} -> note(summary, :deleted, "the audiobook")
      {:error, reason} -> note(summary, :kept, "the audiobook: #{inspect(reason)}")
    end
  end

  # A linked book was already in the library and is never touched. A created
  # one goes, unless a second recording has since joined it — `delete_book/1`
  # answers that itself rather than us racing it with a count.
  defp drop_book(summary, %Draft{work: %{mode: :create}}, %Media.Media{book_id: book_id}) do
    case Repo.get(Book, book_id) do
      nil ->
        summary

      book ->
        case Books.delete_book(book) do
          {:ok, _book} -> note(summary, :deleted, "the book")
          {:error, :has_media} -> note(summary, :kept, "the book: another audiobook uses it")
          {:error, reason} -> note(summary, :kept, "the book: #{inspect(reason)}")
        end
    end
  end

  defp drop_book(summary, _draft, _media), do: summary

  defp drop_series(summary, %Draft{work: %{series: links}}) do
    Enum.reduce(links, summary, fn
      %SeriesLink{mode: :create, name: name}, summary -> drop_series_named(summary, name)
      _linked_or_removed, summary -> summary
    end)
  end

  defp drop_series(summary, _draft), do: summary

  defp drop_series_named(summary, name) do
    case Repo.one(from s in Series, where: s.name == ^name, preload: :series_books) do
      %Series{series_books: []} = series ->
        case Books.delete_series(series) do
          {:ok, _series} -> note(summary, :deleted, "the series #{name}")
          {:error, reason} -> note(summary, :kept, "the series #{name}: #{inspect(reason)}")
        end

      %Series{} ->
        note(summary, :kept, "the series #{name}: other books are in it")

      nil ->
        summary
    end
  end

  # People before identities: `People.delete_person/1` deletes the authors
  # that exist only for this human, which is most of them, and cascades their
  # narrator rows. What is left over afterwards is a composite pen name whose
  # other half survives, which `drop_identities/2` sweeps.
  defp drop_people(summary, %Draft{people: people}) do
    Enum.reduce(people, summary, fn
      %PersonDecision{mode: :create} = decision, summary ->
        drop_person(summary, Draft.Field.value(decision.name))

      _linked, summary ->
        summary
    end)
  end

  defp drop_people(summary, _draft), do: summary

  defp drop_person(summary, nil), do: summary

  defp drop_person(summary, name) do
    case Repo.all(from p in Person, where: p.name == ^name) do
      [%Person{} = person] ->
        case People.delete_person(person) do
          {:ok, _person} ->
            note(summary, :deleted, "the person #{name}")

          {:error, reason} ->
            note(summary, :kept, "the person #{name}: #{undo_reason(reason)}")
        end

      [] ->
        summary

      several ->
        # Two humans of one name is exactly the case the split control
        # exists for, and guessing which one this import made would be a
        # coin flip with somebody's curation on the other side.
        note(summary, :kept, "the person #{name}: #{length(several)} people share that name")
    end
  end

  # Identities the import created that nothing points at any more. Deleted by
  # name and only when bare, because an identity is the one record here with
  # no owner: `Author` belongs to no person in the composite case, and a
  # narrator identity outlives the media that referenced it.
  defp drop_identities(summary, %Draft{} = draft) do
    credits =
      ((draft.work && draft.work.authors) || []) ++
        ((draft.recording && draft.recording.narrators) || [])

    Enum.reduce(credits, summary, fn
      %Credit{mode: :create, kind: kind, name: name}, summary ->
        drop_identity(summary, kind, name)

      _linked, summary ->
        summary
    end)
  end

  defp drop_identities(summary, _draft), do: summary

  defp drop_identity(summary, :author, name) do
    case Repo.one(from a in Author, where: a.name == ^name, preload: [:books, :author_people]) do
      %Author{books: [], author_people: []} = author ->
        Repo.delete!(author)
        note(summary, :deleted, "the author #{name}")

      _still_used_or_absent ->
        summary
    end
  end

  defp drop_identity(summary, :narrator, name) do
    case Repo.one(from n in Narrator, where: n.name == ^name, preload: :media) do
      %Narrator{media: []} = narrator ->
        Repo.delete!(narrator)
        note(summary, :deleted, "the narrator #{name}")

      _still_used_or_absent ->
        summary
    end
  end

  ## the item

  # The draft is kept deliberately. The point of undoing is to run the same
  # decisions again with the form changed underneath them; rebuilding from
  # the providers is what "Start over" is for, and it stays one click away.
  defp requeue(%InboxItem{} = item) do
    item
    |> InboxItem.changeset(%{status: :pending, media_id: nil, issue: nil})
    |> Repo.update()
  end

  defp note(summary, key, words), do: Map.update!(summary, key, &[words | &1])

  defp undo_reason(:has_authored_books), do: "they still have books"
  defp undo_reason(:has_narrated_media), do: "they have narrated something else"
  defp undo_reason(other), do: inspect(other)
end
