defmodule Ambry.Inbox.Duplicates do
  @moduledoc """
  What the library is holding twice.

  A report, not a constraint. Two different people genuinely can share a name
  and two different books a title, so a unique index on `people.name` would be
  wrong rather than merely strict. The one real uniqueness the library has is
  `recording_groups (book_id, name)`, which is why sets are absent here.

  Duplication is instead prevented by decisions — the seeder links rather than
  creates, `Seed.relink/2` re-points a proposal when a sibling import makes
  its target exist, `Preflight` asks before the button — every one of which is
  best-effort by construction. This is the measurement.

  Sameness is asked the way matching asks it: `AutoMatch.person_key/1`,
  `AutoMatch.title_key/1` and `AutoMatch.same_series?/2`, the same functions
  that decide whether an import links or creates. A second definition here is
  the drift that would let the report and the importer disagree. It follows
  that this finds records the queue never touched, whatever created them.

  Each record says what points at it, because the question a found pair raises
  is "which one can go", answered by the one nothing references.

  Not every pair is a mistake: `same_series?/2` folds a subtitle head and
  filler words, so it pairs a companion series with its parent. So the answer
  is a decision, recorded — `dismiss/2` settles one set and `restore/2` puts
  it back. A dismissal names its exact members, so a set that later gains one
  asks again.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.DuplicateDismissal
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  @typedoc """
  One record the library holds, and what references it.

  `uses` is keyed by the word for the thing counted. An author or narrator
  also carries `person_id`, the human behind the identity when exactly one
  is, because that is where either is edited.
  """
  @type entry :: %{
          :id => integer(),
          :name => String.t(),
          :uses => %{atom() => non_neg_integer()},
          optional(:person_id) => integer() | nil
        }

  @type group :: %{kind: kind(), records: [entry()]}

  @type kind :: :person | :author | :narrator | :book | :series

  @doc """
  Every set of records that name the same thing: people, authors, narrators,
  books, series, worst first within a kind.

  Sets marked intentional are not here; see `report/0`.
  """
  @spec check() :: [group()]
  def check, do: report().found

  @doc """
  The findings, and the sets that have been answered, from one pass.

  Both halves in one call because `groups/0` reads five tables whole and the
  page shows both.
  """
  @spec report() :: %{found: [group()], dismissed: [group()]}
  def report do
    dismissed = dismissals()
    {settled, found} = Enum.split_with(groups(), &dismissed?(&1, dismissed))

    %{
      found: Enum.map(found, &records_with_uses/1),
      dismissed: Enum.map(settled, &records_with_uses/1)
    }
  end

  @doc """
  How many sets are still asking a question, without asking what references
  them. For the overview, which only needs to know whether there is anything
  to say.
  """
  @spec count() :: non_neg_integer()
  def count do
    dismissed = dismissals()
    Enum.count(groups(), &(not dismissed?(&1, dismissed)))
  end

  @doc """
  Records this set as intentional, so the report stops asking about it.

  Idempotent: the page it is clicked from can be open in two tabs.
  """
  @spec dismiss(kind(), [integer()]) :: :ok
  def dismiss(kind, record_ids) do
    Repo.insert!(
      %DuplicateDismissal{
        kind: kind,
        record_ids: Enum.sort(record_ids),
        dismissed_at: DateTime.truncate(DateTime.utc_now(), :second)
      },
      on_conflict: :nothing,
      conflict_target: [:kind, :record_ids]
    )

    :ok
  end

  @doc """
  Puts a set back into the report.
  """
  @spec restore(kind(), [integer()]) :: :ok
  def restore(kind, record_ids) do
    ids = Enum.sort(record_ids)

    Repo.delete_all(from d in DuplicateDismissal, where: d.kind == ^kind and d.record_ids == ^ids)

    :ok
  end

  @doc """
  What was examined, so a report of nothing can say what nothing covers.
  """
  @spec scanned() :: %{atom() => non_neg_integer()}
  def scanned do
    %{
      people: Repo.aggregate(Person, :count),
      authors: Repo.aggregate(Author, :count),
      narrators: Repo.aggregate(Narrator, :count),
      books: Repo.aggregate(Book, :count),
      series: Repo.aggregate(Series, :count)
    }
  end

  ## what has been answered

  # Keyed on the members, not the key they folded together on: a set that
  # gains a third member is one nobody has looked at.
  defp dismissed?(%{kind: kind, records: records}, dismissals),
    do: MapSet.member?(dismissals, {kind, records |> Enum.map(& &1.id) |> Enum.sort()})

  defp dismissals do
    DuplicateDismissal
    |> select([d], {d.kind, d.record_ids})
    |> Repo.all()
    |> MapSet.new()
  end

  defp records_with_uses(%{kind: kind, records: records}),
    do: %{kind: kind, records: Enum.map(records, &with_uses(kind, &1))}

  ## finding them

  defp groups do
    by_key(:person, Person, & &1.name, &AutoMatch.person_key/1) ++
      by_key(:author, Author, & &1.name, &AutoMatch.person_key/1) ++
      by_key(:narrator, Narrator, & &1.name, &AutoMatch.person_key/1) ++
      by_key(:book, Book, & &1.title, &AutoMatch.title_key/1) ++
      series_groups()
  end

  # Whole-table reads: the keys are Elixir functions, and asking in SQL would
  # mean a second spelling of each rule.
  defp by_key(kind, schema, name, key) do
    schema
    |> Repo.all()
    |> Enum.map(&%{id: &1.id, name: name.(&1)})
    |> Enum.group_by(&key.(&1.name))
    |> Enum.filter(fn {_key, records} -> length(records) > 1 end)
    |> Enum.sort_by(fn {key, _records} -> key end)
    |> Enum.map(fn {_key, records} -> %{kind: kind, records: Enum.sort_by(records, & &1.id)} end)
  end

  # `same_series?/2` is a predicate, not a key, so the groups are built by
  # absorption rather than by grouping on a value.
  defp series_groups do
    Series
    |> Repo.all()
    |> Enum.map(&%{id: &1.id, name: &1.name})
    |> Enum.reduce([], &absorb/2)
    |> Enum.filter(&(length(&1) > 1))
    |> Enum.map(&%{kind: :series, records: Enum.sort_by(&1, fn record -> record.id end)})
    |> Enum.sort_by(&hd(&1.records).id)
  end

  defp absorb(record, groups) do
    {related, rest} =
      Enum.split_with(groups, fn group ->
        Enum.any?(group, &AutoMatch.same_series?(&1.name, record.name))
      end)

    [[record | List.flatten(related)] | rest]
  end

  ## what points at them

  # One query per record, and only for records already known to collide.
  defp with_uses(:person, record),
    do:
      Map.put(record, :uses, %{
        authors: through(Person, record, :authors),
        narrators: through(Person, record, :narrators)
      })

  defp with_uses(:author, record) do
    record
    |> Map.put(:uses, %{books: through(Author, record, :books)})
    |> Map.put(:person_id, sole_person(record))
  end

  defp with_uses(:narrator, %{id: id} = record) do
    record
    |> Map.put(:uses, %{audiobooks: through(Narrator, record, :media)})
    |> Map.put(:person_id, Repo.one(from n in Narrator, where: n.id == ^id, select: n.person_id))
  end

  defp with_uses(:book, record),
    do: Map.put(record, :uses, %{audiobooks: through(Book, record, :media)})

  defp with_uses(:series, record),
    do: Map.put(record, :uses, %{books: through(Series, record, :books)})

  # Only when the answer is one human: a composite pen name has no single
  # page to send anybody to. Same rule as `Preflight.sole_person/1`.
  defp sole_person(%{id: id}) do
    Author
    |> where([a], a.id == ^id)
    |> join(:inner, [a], p in assoc(a, :people))
    |> select([_a, p], p.id)
    |> Repo.all()
    |> case do
      [person_id] -> person_id
      _none_or_several -> nil
    end
  end

  defp through(schema, %{id: id}, association) do
    schema
    |> where([r], r.id == ^id)
    |> join(:left, [r], related in assoc(r, ^association))
    |> select([_r, related], count(related.id))
    |> Repo.one()
  end
end
