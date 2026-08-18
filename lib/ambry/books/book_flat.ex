defmodule Ambry.Books.BookFlat do
  @moduledoc """
  A flattened view of books.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.Books.SeriesBookType
  alias Ambry.People.PersonName
  alias Ambry.Search.Query

  schema "books_flat" do
    field :title, :string
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]
    field :thumbnails, {:array, :string}
    field :authors, {:array, PersonName.Type}
    field :series, {:array, SeriesBookType.Type}
    field :universes, :string
    field :media, :integer

    # deprecated
    field :image_path, :string
    field :has_description, :boolean

    timestamps(type: :utc_datetime)
  end

  @doc """
  Books ranked by how many of the given keywords they match.

  The substring search below asks whether one whole string appears inside one
  field, which is the right question for a person typing and the wrong one for
  matching a file against the library: a tag title is rarely the library's
  title. Measured on the operator's own uploads, the file for Harry Potter and
  the Philosopher's Stone is tagged `HP1 - The Philosopher's Stone` — a shelf
  label, not a title — and no substring of it appears in the book's real title.
  Neither did the title-space-author string the inbox used to search with,
  which cannot match anything at all because it is not a substring of any one
  field.

  Keywords fix both: a term that misses costs nothing, a term that hits earns
  a point, and the author's name goes from breaking the search to improving
  the ranking. Ordering is by hits, so the caller still gets its candidates
  best-first; the fine-grained scoring stays where it was.
  """
  def by_keywords([], _limit), do: from(b in __MODULE__, where: false)

  def by_keywords(terms, limit) do
    hits = keyword_hits(terms)

    # Interpolated as a whole keyword list: `order_by` takes a dynamic only in
    # that form, not as a value inside a literal list.
    order = [desc: hits, asc: dynamic([b], b.title)]

    from(b in __MODULE__,
      where: ^dynamic(^hits > 0),
      order_by: ^order,
      limit: ^limit
    )
  end

  # Summed as one expression so it can both filter and order without the
  # matching being written down twice.
  defp keyword_hits(terms) do
    Enum.reduce(terms, dynamic([_b], 0), fn term, acc ->
      dynamic(^acc + ^term_hit(term))
    end)
  end

  defp term_hit(term) do
    pattern = "%#{term}%"

    dynamic(
      [b],
      fragment(
        """
        (CASE WHEN ? ILIKE ?
               OR ? ILIKE ?
               OR EXISTS (SELECT FROM unnest(?) e WHERE (e).name ILIKE ? OR (e).person_name ILIKE ?)
               OR EXISTS (SELECT FROM unnest(?) e WHERE (e).name ILIKE ?)
              THEN 1 ELSE 0 END)
        """,
        b.title,
        ^pattern,
        b.universes,
        ^pattern,
        b.authors,
        ^pattern,
        ^pattern,
        b.series,
        ^pattern
      )
    )
  end

  @doc """
  Splits a phrase into the keywords worth matching on.

  Punctuation goes (an apostrophe is typographic or straight depending on who
  wrote the file) and so do the words every title contains, which would
  otherwise score a point against everything in the library.
  """
  @stopwords ~w(a an and at by for from in of on or the to with)

  def keywords(nil), do: []

  def keywords(phrase) when is_binary(phrase) do
    phrase
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(&(&1 in @stopwords or String.length(&1) < 2))
    |> Enum.uniq()
  end

  def filter(query, :search, search_string) do
    from b in query,
      where: b.id in subquery(Query.ids(search_string, :book))
  end
end
