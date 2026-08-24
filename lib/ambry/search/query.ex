defmodule Ambry.Search.Query do
  @moduledoc """
  The index, as something a caller can compose with.

  Every search in the app comes through here. `build/2` returns a composable
  `Ecto.Query` over the index, so a picker, a list filter and the matcher
  share one definition of searching.

  ## Two knobs and a policy

    * **`:joiner`** — `:all` (every term must match) or `:any` (a term that
      misses costs nothing, a term that hits improves the rank). `:any` is
      what lets "sanderson kings" find The Way of Kings.
    * **`:partial`** — opens the last term to a prefix match, so "sander"
      finds Sanderson. Prefix, not substring: "anderson" does not.
    * **`:narrowing`** is the picker's policy over the two: ask `:all`, widen
      to `:any` only if nothing answers. `:any` alone gets the relationship
      backwards, since every word added *adds* results.

  Plus `:types`, to scope to one kind of record.

  An empty phrase is not a failed search: `ambry_tsquery` returns NULL for a
  phrase with no lexemes and `build/2` reads that as "everything,
  alphabetically".

  ## Ranking

  `ts_rank_cd` over the A/B/C weights, with `pg_trgm` similarity as a tiebreak
  and the record's own name last for stability.

  Ahead of all of it, two booleans: does the name **start with** the raw
  phrase, and failing that, **contain** it. Word order and adjacency are what
  a `tsvector` throws away and a picker lives on. They read the raw phrase,
  the only place a stop word still counts, and cannot widen a result set.

  Deliberately not length-normalized: the trigram tiebreak already favours a
  shorter string, and normalizing ranks a two-lexeme person above the book
  matching both words. Coverage beats brevity; brevity only breaks ties.
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

  Settles the index first; outside test that compiles to nothing.
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

  `:narrowing` is two queries and so cannot be a composable one, which is why
  it lives here rather than in `build/2`.
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

  # **No emptiness guard.** A phrase producing no lexemes matches nothing,
  # which `@@ NULL` already says. Guarded, a word the stemmer drops would
  # return the entire library: "nothing typed" and "typed something the index
  # cannot hold" are different answers.
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

  What an admin list filter needs. Ordering is dropped, since the list has
  its own sort.
  """
  def ids(phrase, type, opts \\ []) do
    phrase
    |> build(Keyword.put(opts, :types, [type]))
    |> exclude(:order_by)
    |> select([record], fragment("(?).id", record.reference))
  end

  @doc """
  Rows of `queryable` matching `phrase`, best first, for a picker.

  A typeahead is ranking and nothing else, so the defaults are `:narrowing`
  and `partial: true`.

  `queryable` is whatever the caller wants back, matched on `id`. The index's
  order is reapplied after the fetch, since a `WHERE id IN` does not keep it.
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
