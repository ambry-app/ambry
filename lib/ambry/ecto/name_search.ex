defmodule Ambry.Ecto.NameSearch do
  @moduledoc """
  Narrowing a typeahead's options to what somebody typed, in one place.

  Every picker in the admin asks the same question of a different table — "the
  records whose name looks like this, best first" — and it used to be asked in
  Elixir over a preloaded list of every row in that table. That works until
  the table is the library: a resolver over books loaded every book, with its
  cover, on every form mount.

  Two properties are worth keeping from the version this replaces, because
  losing either would be a visible regression:

    * **Accents fold.** "Rodriguez" finds "Patricia Rodríguez" — the library's
      spelling and a file's are one narrator. `unaccent` is the SQL twin of
      the NFD fold, the same pairing `Ambry.Inbox.AutoMatch.person_key/1` and
      its `@name_key_sql` already rely on.
    * **A prefix beats a substring.** Typing "Kra" puts "Kramer" above
      "Michael Kramer" rather than sorting them alphabetically together.

  An empty phrase is not a failed search: it's a box the operator has just
  focused, and what belongs there is the first page of records rather than
  nothing.
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

  @doc """
  The `LIKE` pattern for a phrase, for a caller whose searchable expression
  isn't a single column.

  A recording's label is `coalesce(title, book.title)` — two columns and a
  fallback — which no field-name parameter can express, so those callers write
  the fragment and take the escaping from here.
  """
  def pattern(phrase), do: "%#{escape(String.trim(phrase || ""))}%"

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
