defmodule Ambry.Search.Drain do
  @moduledoc """
  Turns dirty references into rebuilt search records.

  The triggers that fill `Ambry.Search.Queue` are deliberately stupid: a row
  enqueues the references its own columns name, and nothing fans out in SQL.
  All the graph knowledge is here, in Elixir, where it can be read and tested.

  ## What expands into what

  The index holds one record per book, series and person, and each record
  quotes rows the trigger cannot see from where it fires:

    * a **book** record quotes its media's titles, its series' names, its
      authors' and narrators' names, and the names of the people behind them
    * a **series** record quotes the names of its books' authors, and the
      people behind them
    * a **person** record quotes their author and narrator pen names

  So the expansion is two hops at most, and deliberately not a closure:

      direct books  = books, media's books, a series' books is NOT this,
                      an author's/narrator's/person's/universe's books
      direct series = series
      books  = direct books ∪ books of direct series
      series = direct series ∪ series of direct books

  A series rename changes its books' `secondary`, so it pulls its books in. A
  book change can change its series' `secondary` (the series quotes its books'
  authors) or empty the series entirely, so it pulls its series in. Neither
  needs to go further: the books reached through a series did not themselves
  change, and the series reached through a book did not change name.

  ## Author and narrator are not symmetric

  `narrators.person_id` is a column — one person per narrator. Authors reach
  people through `authors_people`, because a composite author is several
  people writing under one name. So narrator→person is a read and
  author→person is a join, and the two cannot share a code path.
  """

  import Ecto.Query

  alias Ambry.Books.BookUniverse
  alias Ambry.Books.SeriesBook
  alias Ambry.Media.Media
  alias Ambry.Media.MediaNarrator
  alias Ambry.People.AuthorPerson
  alias Ambry.People.BookAuthor
  alias Ambry.People.Narrator
  alias Ambry.Repo
  alias Ambry.Search.Index
  alias Ambry.Search.Queue

  require Logger

  @batch_size 500

  @doc """
  Waits for the index to reflect everything written so far.

  In production a no-op: `Ambry.Search.Listener` has already drained, or is
  about to, and no read should be waiting on it. In test there is no listener
  — the SQL sandbox holds every write in a transaction that never commits, so
  the `NOTIFY` the enqueue trigger raises is never delivered and an Oban job
  never runs — so this drains inline.

  Called from `Ambry.Search.Query.build/2`, which every read path composes
  from, rather than from the tests themselves. A test that writes and then
  searches is then in the same position as a caller a millisecond later,
  without having to know that a queue exists.
  """
  if Application.compile_env(:ambry, [Ambry.Search, :settle_inline], false) do
    def settle do
      {:ok, _count} = run()
      :ok
    end
  else
    def settle, do: :ok
  end

  @doc """
  Drains the queue until it is empty, returning how many references it took.

  Each batch claims and rebuilds inside one transaction, so a rebuild that
  raises puts its references back rather than dropping them on the floor. The
  loop is bounded by the queue: nothing re-enqueues what it just drained,
  because `search_index` has no trigger on it.
  """
  def run(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)

    drained = drain_batches(batch_size, 0)

    if drained > 0 do
      Logger.debug(fn -> "Search index: rebuilt from #{drained} dirty references" end)
    end

    {:ok, drained}
  end

  defp drain_batches(batch_size, total) do
    claimed =
      Repo.transaction(fn ->
        case Queue.claim(batch_size) do
          [] ->
            0

          references ->
            references |> group() |> rebuild!()
            length(references)
        end
      end)

    case claimed do
      {:ok, 0} -> total
      {:ok, count} -> drain_batches(batch_size, total + count)
    end
  end

  defp group(references) do
    Enum.group_by(references, &elem(&1, 0), &elem(&1, 1))
  end

  defp rebuild!(grouped) do
    direct_books = direct_books(grouped)
    direct_series = ids(grouped, :series)

    books = combine(direct_books, books_of_series(direct_series))
    series = combine(direct_series, series_of_books(direct_books))
    people = people(grouped)

    Index.index!(:book, books)
    Index.index!(:series, series)
    Index.index!(:person, people)
  end

  # Everything whose change can alter a book record, resolved to book ids.
  defp direct_books(grouped) do
    [
      ids(grouped, :book),
      books_of_media(ids(grouped, :media)),
      books_of_universe(ids(grouped, :universe)),
      books_of_author(ids(grouped, :author)),
      books_of_narrator(ids(grouped, :narrator)),
      books_of_person(ids(grouped, :person))
    ]
    |> Enum.reduce(&combine/2)
  end

  # A person record is the person's own pen names, so a change to any author
  # or narrator identity behind them rebuilds it.
  defp people(grouped) do
    [
      ids(grouped, :person),
      people_of_author(ids(grouped, :author)),
      people_of_narrator(ids(grouped, :narrator))
    ]
    |> Enum.reduce(&combine/2)
  end

  defp ids(grouped, type), do: Map.get(grouped, type, [])

  defp combine(a, b), do: a |> Enum.concat(b) |> Enum.uniq()

  defp all(query), do: query |> Repo.all() |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp books_of_media([]), do: []

  defp books_of_media(media_ids) do
    all(from(m in Media, where: m.id in ^media_ids, select: m.book_id))
  end

  defp books_of_series([]), do: []

  defp books_of_series(series_ids) do
    all(from(sb in SeriesBook, where: sb.series_id in ^series_ids, select: sb.book_id))
  end

  defp series_of_books([]), do: []

  defp series_of_books(book_ids) do
    all(from(sb in SeriesBook, where: sb.book_id in ^book_ids, select: sb.series_id))
  end

  defp books_of_universe([]), do: []

  defp books_of_universe(universe_ids) do
    all(from(bu in BookUniverse, where: bu.universe_id in ^universe_ids, select: bu.book_id))
  end

  defp books_of_author([]), do: []

  defp books_of_author(author_ids) do
    all(from(ba in BookAuthor, where: ba.author_id in ^author_ids, select: ba.book_id))
  end

  defp books_of_narrator([]), do: []

  defp books_of_narrator(narrator_ids) do
    all(
      from(mn in MediaNarrator,
        join: m in Media,
        on: m.id == mn.media_id,
        where: mn.narrator_id in ^narrator_ids,
        select: m.book_id
      )
    )
  end

  # Both roads at once: the books this person wrote under any pen name, and
  # the books they narrated.
  defp books_of_person([]), do: []

  defp books_of_person(person_ids) do
    authored =
      all(
        from(ap in AuthorPerson,
          join: ba in BookAuthor,
          on: ba.author_id == ap.author_id,
          where: ap.person_id in ^person_ids,
          select: ba.book_id
        )
      )

    narrated =
      all(
        from(n in Narrator,
          join: mn in MediaNarrator,
          on: mn.narrator_id == n.id,
          join: m in Media,
          on: m.id == mn.media_id,
          where: n.person_id in ^person_ids,
          select: m.book_id
        )
      )

    combine(authored, narrated)
  end

  defp people_of_author([]), do: []

  defp people_of_author(author_ids) do
    all(from(ap in AuthorPerson, where: ap.author_id in ^author_ids, select: ap.person_id))
  end

  defp people_of_narrator([]), do: []

  defp people_of_narrator(narrator_ids) do
    all(from(n in Narrator, where: n.id in ^narrator_ids, select: n.person_id))
  end

  @doc """
  Marks the whole library dirty and drains it.

  The reindex button, and what the initial migration leans on: it enqueues in
  SQL and the first drain after boot does the rest.
  """
  def reindex_all! do
    :ok = Queue.enqueue_all!()
    run()
  end
end
