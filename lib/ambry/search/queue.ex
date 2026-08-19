defmodule Ambry.Search.Queue do
  @moduledoc """
  The list of search records a write has invalidated.

  Filled by row triggers on every table the index reads, drained by
  `Ambry.Search.Drain`. Two columns and a composite primary key: a reference
  is dirty or it isn't, and enqueueing the same one twice is free.

  The point of the table is that it is filled *below* the application. Ambry
  writes to `books`, `people` and their joins from several places — the admin
  contexts, `Ambry.Inbox.Importer`, replacement, organizing — and the importer
  in particular is walled off from `Ambry.Search` by its boundary. A trigger
  cannot be walled off and cannot be forgotten.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Books.Universe
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  @doc """
  Takes up to `limit` references off the queue, deleting them.

  `FOR UPDATE SKIP LOCKED` so the cron backstop and the listener can drain at
  the same time without doing each other's work or waiting on it. The delete
  is the claim, so it has to run inside the same transaction as the rebuild it
  feeds: a rebuild that raises rolls the rows back onto the queue rather than
  losing them.
  """
  def claim(limit) do
    %{rows: rows} =
      Repo.query!(
        """
        DELETE FROM search_index_queue
        WHERE (type, id) IN (
          SELECT type, id FROM search_index_queue
          ORDER BY type, id
          LIMIT $1
          FOR UPDATE SKIP LOCKED
        )
        RETURNING type, id
        """,
        [limit]
      )

    Enum.map(rows, fn [type, id] -> {reference_type(type), id} end)
  end

  # Spelled out rather than `String.to_existing_atom/1`: this is the whole
  # set of things a trigger may enqueue, and an unknown one is a migration
  # and a drain that disagree, which should be loud.
  defp reference_type("book"), do: :book
  defp reference_type("media"), do: :media
  defp reference_type("series"), do: :series
  defp reference_type("universe"), do: :universe
  defp reference_type("author"), do: :author
  defp reference_type("narrator"), do: :narrator
  defp reference_type("person"), do: :person

  @doc """
  Marks every record in the library dirty.

  What "reindex everything" means now: the drain does the rest. This replaces
  `refresh_entire_index!/0`, which deleted the whole table and rebuilt it
  inline on every boot — during which search returned nothing.
  """
  def enqueue_all! do
    enqueue_all!(:book, from(b in Book, select: b.id))
    enqueue_all!(:series, from(s in Series, select: s.id))
    enqueue_all!(:universe, from(u in Universe, select: u.id))
    enqueue_all!(:person, from(p in Person, select: p.id))
    enqueue_all!(:author, from(a in Author, select: a.id))
    enqueue_all!(:narrator, from(n in Narrator, select: n.id))

    :ok
  end

  defp enqueue_all!(type, id_query) do
    entries = id_query |> Repo.all() |> Enum.map(&%{type: to_string(type), id: &1})

    entries
    |> Enum.chunk_every(1000)
    |> Enum.each(&Repo.insert_all("search_index_queue", &1, on_conflict: :nothing))
  end
end
