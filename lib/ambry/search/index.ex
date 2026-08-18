defmodule Ambry.Search.Index do
  @moduledoc """
  What a search record is made of, and how it gets written.

  Called only by `Ambry.Search.Drain`, which decides *which* records need
  rebuilding; this module decides what goes in one. The split matters because
  the two questions go stale for different reasons — the graph changes when a
  schema gains an association, the record shape changes when somebody decides
  a new field should be searchable.

  ## Weights

  Each record is three text columns, which the `update_index_search_vector`
  trigger turns into a weighted `tsvector`:

    * `primary` (A) — the thing's own name: a book's title, a person's pen
      names, a series' or universe's name
    * `secondary` (B) — the names it is credited alongside
    * `tertiary` (C) — the real people behind those credits, when they are
      named differently

  ## Rebuilding is also pruning

  `index!/2` is given the ids the drain thinks are dirty, not the ids that
  exist. A book that was deleted arrives here as an id with no row, and the
  answer is to delete its record — which is how deletion works now that
  nothing calls a `Search.delete/1` by hand.

  ## Everything that exists is indexed, including empty shelves

  A series or universe with no books used to be left out, so that user search
  would not offer a dead link. That rule cannot survive the admin lists
  moving onto the index: an empty series is *precisely* what an operator
  opens the series list to find, and it would have been the one row search
  could not reach.

  Nothing is lost by dropping it. `AmbryWeb.SearchLive` already hides a
  series none of whose books have a ready edition, which an empty one
  trivially is — the prune was a second copy of a rule the view already
  enforces, in the one place where it was wrong.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Books.Universe
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo
  alias Ambry.Search.Record
  alias Ambry.Search.Reference

  @doc """
  Rebuilds the records for `ids` of `type`, deleting the ones with nothing
  behind them.
  """
  def index!(_type, []), do: :ok

  def index!(:book, book_ids) do
    books =
      Repo.all(
        from book in Book,
          where: book.id in ^book_ids,
          preload: [:series, :universes, authors: [:people], media: [narrators: [:person]]]
      )

    write!(:book, book_ids, books, &book_record/1)
  end

  def index!(:person, person_ids) do
    people =
      Repo.all(
        from person in Person,
          where: person.id in ^person_ids,
          preload: [:authors, :narrators]
      )

    write!(:person, person_ids, people, &person_record/1)
  end

  def index!(:series, series_ids) do
    series =
      Repo.all(
        from series in Series,
          where: series.id in ^series_ids,
          preload: [:series_books, authors: [:people]]
      )

    write!(:series, series_ids, series, &series_record/1)
  end

  def index!(:universe, universe_ids) do
    universes =
      Repo.all(
        from universe in Universe,
          where: universe.id in ^universe_ids,
          preload: [books: [authors: [:people]]]
      )

    write!(:universe, universe_ids, universes, &universe_record/1)
  end

  defp write!(type, requested_ids, found, record_fun) do
    found_ids = MapSet.new(found, & &1.id)

    requested_ids
    |> Enum.reject(&MapSet.member?(found_ids, &1))
    |> then(&delete!(type, &1))

    found
    |> Enum.map(record_fun)
    |> insert_records!()
  end

  defp delete!(_type, []), do: :ok

  defp delete!(type, ids) do
    type = to_string(type)

    {_count, nil} =
      Repo.delete_all(
        from record in Record,
          where:
            fragment("(?).type = ?", record.reference, ^type) and
              fragment("(?).id = ANY(?)", record.reference, ^ids)
      )

    :ok
  end

  defp book_record(book) do
    narrators = Enum.flat_map(book.media, & &1.narrators)

    secondary_names = names(book.series ++ book.universes ++ book.authors ++ narrators)
    tertiary_names = person_names(book.authors ++ narrators)

    # recording display-title overrides are searchable alongside the book
    # title (e.g. find "Sorcerer's Stone" under the British-titled book)
    media_titles = book.media |> Enum.map(& &1.title) |> Enum.filter(& &1)

    %{
      reference: Reference.new(book),
      primary: join(Enum.uniq([book.title | media_titles])),
      secondary: join(secondary_names),
      tertiary: join(tertiary_names)
    }
  end

  defp person_record(person) do
    person_name = person.name
    author_names = Enum.map(person.authors, & &1.name)
    narrator_names = Enum.map(person.narrators, & &1.name)

    {primary, secondary} =
      case join(author_names ++ narrator_names) do
        nil ->
          {person_name, nil}

        names ->
          {names,
           if(person_name not in author_names and person_name not in narrator_names,
             do: person_name
           )}
      end

    %{
      reference: Reference.new(person),
      primary: primary,
      secondary: secondary
    }
  end

  defp series_record(series) do
    %{
      reference: Reference.new(series),
      primary: series.name,
      secondary: join(names(series.authors)),
      tertiary: join(person_names(series.authors))
    }
  end

  # A universe is found by its own name and by who writes in it — the same
  # shape as a series, for the same reason: "the Sanderson one" is how people
  # remember a shelf they cannot name.
  defp universe_record(universe) do
    authors = Enum.flat_map(universe.books, & &1.authors)

    %{
      reference: Reference.new(universe),
      primary: universe.name,
      secondary: join(names(authors)),
      tertiary: join(person_names(authors))
    }
  end

  defp names(structs), do: structs |> Enum.map(& &1.name) |> Enum.uniq()

  # The real people behind a credit, named only when they are named
  # differently — a pen name that matches the person adds nothing.
  defp person_names(authors_or_narrators) do
    authors_or_narrators
    |> Enum.flat_map(fn identity ->
      identity
      |> people_of()
      |> Enum.reject(&(&1.name == identity.name))
    end)
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end

  defp people_of(%Author{people: people}), do: people
  defp people_of(%Narrator{person: person}), do: [person]

  defp join([]), do: nil
  defp join(items), do: Enum.join(items, " ")

  defp insert_records!(records) do
    records
    |> Enum.chunk_every(100)
    |> Enum.each(fn records ->
      {_count, nil} =
        Repo.insert_all(Record, records,
          on_conflict: {:replace_all_except, [:reference]},
          conflict_target: [:reference]
        )
    end)

    :ok
  end
end
