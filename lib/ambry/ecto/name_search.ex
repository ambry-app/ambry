defmodule Ambry.Ecto.NameSearch do
  @moduledoc """
  Narrowing a picker's options to what somebody typed, where the thing being
  picked is not a record.

  Three callers, and it is worth saying what they have in common, because
  everything else that once used this now asks `Ambry.Search.Query` instead:

    * `People.search_authors/2` and `People.search_narrators/2` pick a **pen
      name**. An author is not a record in the search index and should not
      be; the index holds the *person*, and a credit is the name they
      published under. A picker choosing between "Ty Franck" and "James S.A.
      Corey" is choosing which name goes on the book, and offering it the
      person behind both would be answering a different question.
    * `Media.search_recording_groups/3` picks a **set within one book**.
      Indexing every set in the library so that a picker can filter the two
      or three belonging to one book would be all cost and no reach.

  So this is not a sixth search engine. It is a name filter over one column
  of one table, and for these three that is exactly the right size. What it
  replaced — loading every row into memory and filtering in Elixir — is the
  thing that was wrong, not the question it asks.

  Two properties are load-bearing:

    * **Accents fold.** "Rodriguez" finds "Patricia Rodríguez" — the
      library's spelling and a file's are one narrator. `unaccent` is the SQL
      twin of the NFD fold, the same pairing `Ambry.Inbox.AutoMatch.person_key/1`
      and its `@name_key_sql` already rely on.
    * **A prefix beats a substring.** Typing "Kra" puts "Kramer" above
      "Michael Kramer" rather than sorting them alphabetically together.

  An empty phrase is not a failed search: it's a box the operator has just
  focused, and what belongs there is the first page of records rather than
  nothing. `Ambry.Search.Query.matching/4` keeps the same promise, so the
  pickers behave alike whichever of the two answers them.
  """

  import Ecto.Query

  @doc """
  Narrows `queryable` to rows whose `field` looks like `phrase`, best first.
  """
  def narrow(queryable, field, phrase, limit) do
    case String.trim(phrase || "") do
      "" -> queryable |> order_by(asc: ^field) |> limit(^limit)
      trimmed -> queryable |> matching(field, trimmed) |> limit(^limit)
    end
  end

  defp matching(queryable, field, phrase) do
    anywhere = "%#{escape(phrase)}%"
    leading = "#{escape(phrase)}%"

    queryable
    |> where([r], fragment("unaccent(?) ILIKE unaccent(?)", field(r, ^field), ^anywhere))
    |> order_by([r],
      asc:
        fragment(
          "CASE WHEN unaccent(?) ILIKE unaccent(?) THEN 0 ELSE 1 END",
          field(r, ^field),
          ^leading
        ),
      asc: field(r, ^field)
    )
  end

  # A name is operator input and `%` is a legal character in one, so the
  # wildcards have to be ours alone — otherwise typing a percent sign matches
  # every row in the table.
  defp escape(phrase), do: String.replace(phrase, ~r/[\\%_]/, "\\\\\\0")
end
