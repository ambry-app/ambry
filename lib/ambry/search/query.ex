defmodule Ambry.Search.Query do
  @moduledoc """
  The index, as something a caller can compose with.

  This is the piece whose absence caused the sprawl. `Ambry.Search` used to
  hand back a materialized list of preloaded structs, which is all a results
  page needs and nothing a picker or an admin list filter can use. So each of
  them grew its own search: `Ambry.Ecto.NameSearch` for typeaheads,
  `BookFlat.by_keywords/2` for auto-match, an `ILIKE` chain per flat view.
  All five are gone; this is what they became.
  `by_keywords/2` had got as far as reimplementing tokenization, a stopword
  list and OR-scored ranking in Ecto dynamics — `ts_rank` spelled the long
  way, over a view no index could serve.

  `build/2` returns an `Ecto.Query` over the index. What a caller does with
  it — hydrate it, `EXISTS` against it, limit it, join to it — is the
  caller's business.

  ## Two knobs and a policy, not five modes

    * **`:joiner`** — `:all` (every term must match) or `:any` (a term that
      misses costs nothing, a term that hits improves the rank). `:any` is
      `by_keywords`' whole idea, indexed and ranked by `ts_rank_cd` instead of
      a hand-summed `CASE`. It is what lets "sanderson kings" find The Way of
      Kings, where an AND of both terms finds nothing.
    * **`:partial`** — opens the last term to a prefix match, so "sander"
      finds Sanderson. This is the prefix property the name pickers used to
      get from a `LIKE 'phrase%'`, and the reason user search can drop the
      `ILIKE` arm it used to carry as a safety net.

      Deliberately prefix and not substring: "anderson" does not find
      Sanderson, per the operator, 2026-08-18. A mid-word match is what an
      `ILIKE '%…%'` buys and nobody wanted it.

    * **`:narrowing`** is not a third joiner so much as the picker's policy
      over the two: ask `:all`, and widen to `:any` only if nothing answers.
      It exists because `:any` alone gets the relationship backwards —
      every word you add *adds* results, when the whole reason you kept
      typing was to remove some. Under `:narrowing` a term narrows right up
      until the constraint is unsatisfiable, and then the box falls back to
      the best partial matches rather than going empty.

  Plus `:types`, to scope to books, or people, or whatever one kind a picker
  is picking.

  ## An empty phrase is not a failed search

  It is a box somebody has just clicked into, and what belongs there is the
  first page of what exists. `ambry_tsquery` returns NULL for a phrase with
  no lexemes in it, and `build/2` reads that as "everything, alphabetically".

  ## Ranking

  `ts_rank_cd` over the A/B/C weights, with the `pg_trgm` `similarity` sum as
  a tiebreak and the record's own name last so the order is stable.

  Ahead of all of it sit two booleans: does the record's name **start with**
  the raw phrase, and failing that, does it **contain** it. This is the one
  signal a `tsvector` throws away and a picker lives on — word order and
  adjacency. Typing "murder" ranked The Thursday Murder Club above Murder by
  Other Means, because that book's series repeats its title and a second
  weight-B hit outscores a single weight-A one; and typing "murder by"
  changed nothing at all, because `by` is a stop word and leaves the query
  entirely.

  They read the *raw* phrase rather than the parsed one on purpose. That
  makes them the only place a stop word still counts and the only place the
  order of the words survives. They cannot widen a result set — they run over
  rows the query already matched — so they only ever decide which of them a
  picker shows first.

  Deliberately *not* length-normalized. Normalization was tried, because it
  looks like the way to keep "Kramer" above "Michael Kramer" for "kra" — but
  the trigram tiebreak already does that, since a shorter string is more
  similar to a short phrase, and normalizing costs something real: it divides
  a two-lexeme person record's rank by less than a five-lexeme book's, so
  "sanderson mistborn" ranked the author above the book that matched both
  words. Coverage should beat brevity; brevity only breaks ties.
  """

  import Ecto.Query

  alias Ambry.Repo
  alias Ambry.Search.Drain
  alias Ambry.Search.Record

  @doc """
  The index, narrowed and ordered, as a composable queryable.

  ## Options

    * `:joiner` — `:all` (default) or `:any`
    * `:partial` — prefix-match the last term, default `false`
    * `:types` — a list of reference types to scope to, e.g. `[:book]`

  Settles the index first, which outside test compiles to nothing — see
  `Ambry.Search.Drain.settle/0`.
  """
  def build(phrase, opts \\ []) do
    :ok = Drain.settle()

    joiner = opts |> Keyword.get(:joiner, :all) |> joiner!()
    partial = Keyword.get(opts, :partial, false)
    phrase = String.trim(phrase || "")

    Record
    |> scope_to_types(Keyword.get(opts, :types))
    |> match(phrase, joiner, partial)
  end

  defp joiner!(joiner) when joiner in [:all, :any], do: to_string(joiner)

  @doc """
  The ids of `type` matching `phrase`, best first, resolving `:narrowing`.

  `build/2` cannot express `:narrowing` — it is two queries, and which one
  answers depends on whether the first found anything — so it lives here,
  where a caller has already accepted that it is fetching rows.
  """
  def ranked_ids(phrase, limit, opts) do
    case Keyword.get(opts, :joiner, :narrowing) do
      :narrowing ->
        case fetch_ids(phrase, limit, Keyword.put(opts, :joiner, :all)) do
          [] -> fetch_ids(phrase, limit, Keyword.put(opts, :joiner, :any))
          ids -> ids
        end

      _joiner ->
        fetch_ids(phrase, limit, opts)
    end
  end

  defp fetch_ids(phrase, limit, opts) do
    phrase
    |> build(opts)
    |> limit(^limit)
    |> select([record], fragment("(?).id", record.reference))
    |> Repo.all()
  end

  defp scope_to_types(query, nil), do: query

  defp scope_to_types(query, types) do
    types = Enum.map(types, &to_string/1)

    where(query, [r], fragment("(?).type = ANY(?)", r.reference, ^types))
  end

  # An empty box is not a failed search: it is one somebody has just clicked
  # into, and the first page is what belongs there.
  defp match(query, "", _joiner, _partial), do: order_by(query, [record], asc: record.primary)

  # A phrase that produced no lexemes matches nothing, and `@@ NULL` being
  # NULL rather than false is exactly that — so this needs no emptiness guard.
  #
  # **It used to have one, and that was a bug.** Treating "no lexemes" as "no
  # phrase" meant a search for a word the stemmer drops returned the entire
  # library, ranked arbitrarily. English's stop list holds `don` (from
  # "don't"), `will`, `can`, `just` and `now` among others, so searching for
  # somebody named Don got every book in the library. "Nothing typed" and
  # "typed something the index cannot hold" are different answers, and only
  # the first is an invitation to browse.
  defp match(query, phrase, joiner, partial) do
    from record in query,
      where:
        fragment(
          "? @@ ambry_tsquery(?, ?, ?)",
          record.search_vector,
          ^phrase,
          ^joiner,
          ^partial
        ),
      order_by: [
        desc:
          fragment(
            "starts_with(unaccent(lower(?)), unaccent(lower(?)))",
            record.primary,
            ^phrase
          ),
        desc:
          fragment(
            "strpos(unaccent(lower(?)), unaccent(lower(?))) > 0",
            record.primary,
            ^phrase
          ),
        desc:
          fragment(
            "ts_rank_cd(?, ambry_tsquery(?, ?, ?))",
            record.search_vector,
            ^phrase,
            ^joiner,
            ^partial
          ),
        desc:
          fragment(
            """
            COALESCE(similarity(?, ?), 0) +
            COALESCE(similarity(?, ?), 0) +
            COALESCE(similarity(?, ?), 0)
            """,
            record.primary,
            ^phrase,
            record.secondary,
            ^phrase,
            record.tertiary,
            ^phrase
          ),
        asc: record.primary
      ]
  end

  @doc """
  The ids of one kind of record matching `phrase`, for an `IN` against a flat
  view.

  What an admin list filter needs. The five of them each had their own
  `ILIKE` chain — one per searchable column, hand-unrolled over the array
  columns, and no two of them agreeing on what "search" meant. They ask the
  index instead now, which is how a list filter picks up punctuation folding
  and accents without anyone writing either down again.

  Ordering is dropped: the list has its own sort, and an `ORDER BY` inside an
  `IN` is work nobody reads.
  """
  def ids(phrase, type, opts \\ []) do
    phrase
    |> build(Keyword.put(opts, :types, [type]))
    |> exclude(:order_by)
    |> select([record], fragment("(?).id", record.reference))
  end

  @doc """
  Rows of `queryable` matching `phrase`, best first, for a picker.

  A picker is a different question from a list filter, which is why this is a
  different function. A list is already narrowed by the operator and sorted
  the way they chose, so `ids/3` throws the ranking away; a typeahead is
  ranking and nothing else — the whole answer is which three rows go at the
  top.

  So the defaults here are the picker's: `:narrowing`, so that another word
  removes rows rather than adding them and a term that misses still cannot
  empty the box, and `partial: true`, because somebody typing has not
  finished the word yet.

  `queryable` is whatever the caller wants back — a schema, or one carrying
  its own preloads — matched on `id`. The index's order is reapplied after
  the fetch, since a `WHERE id IN` does not keep it.
  """
  def matching(queryable, phrase, type, opts \\ []) do
    {limit, build_opts} = Keyword.pop(opts, :limit, 25)

    build_opts =
      build_opts
      |> Keyword.put_new(:joiner, :narrowing)
      |> Keyword.put_new(:partial, true)
      |> Keyword.put(:types, [type])

    ranked_ids = ranked_ids(phrase, limit, build_opts)

    rows =
      queryable
      |> where([row], row.id in ^ranked_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.flat_map(ranked_ids, fn id ->
      case Map.fetch(rows, id) do
        {:ok, row} -> [row]
        :error -> []
      end
    end)
  end
end
