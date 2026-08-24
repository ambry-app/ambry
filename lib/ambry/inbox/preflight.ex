defmodule Ambry.Inbox.Preflight do
  @moduledoc """
  What this import is about to create that the library may already have.

  Every `:create` in a draft is a promise to add a row, and a draft is a
  snapshot of the library taken when the item was matched. Between the
  snapshot and the button the library moves. `Seed.relink/2` closes most of
  that gap, but it only fires after a sibling import, only on uncurated
  decisions, and only where exactly one certain match exists.

  So this is the check at the door: read the draft, ask the library about
  every name it means to create, and hand back what it found. It runs on the
  click, before the job is enqueued.

  It reports and does not decide. A name in common is evidence, and the
  judgement it feeds — same book, or two books that share a title — is the
  operator's, because attaching a recording to the wrong existing book is
  worse than one duplicate Book and much harder to notice.

  ## Identity, not similarity

  Names fold through `AutoMatch.person_key/1` and titles through
  `AutoMatch.title_key/1`, so punctuation, spacing, capitalisation, accents
  and leading articles don't make a different record. Nothing looser is asked:
  a fuzzy match here would ask the operator to dismiss noise on every import,
  and a question worth ignoring is a question that gets ignored.

  A book match carries whether it also shares an author. Both are worth
  showing, but only one is near-certain, and the form ranks them accordingly.

  The book lookup deliberately avoids the search index: `Books.match_books/2`
  reads `search_index`, which `Ambry.Search.Listener` fills asynchronously
  after the writing transaction commits, so a check could silently miss a book
  created moments ago. This reads `books` directly and folds titles in Elixir,
  where the rule is `title_key/1` itself rather than a SQL restatement of it.

  One of these is not a duplicate but a failure: a `:create` set whose name is
  already taken on the same book violates `recording_groups (book_id, name)`
  and fails the import outright. Reporting it here turns a crash into a
  question.
  """

  import Ambry.Inbox.AutoMatch, only: [person_key_sql: 1]
  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.Media.RecordingGroup
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  @typedoc """
  One thing this import would create, and what the library already has under
  that name.

  `certain?` is about the strength of the match, never about what to do with
  it.
  """
  @type finding :: %{
          kind: :book | :series | :author | :narrator | :person | :set,
          section: :work | :recording | :people,
          label: String.t(),
          certain?: boolean(),
          matches: [match()]
        }

  @type match :: %{
          label: String.t(),
          route: {:book | :series | :set | :person, integer()} | nil
        }

  @doc """
  Everything this item would create that the library may already have.

  Ordered book, series, authors, set, narrators, people, because the list is
  compared for equality when the operator says to go ahead anyway.
  """
  @spec check(struct() | nil) :: [finding()]
  def check(nil), do: []
  def check(%InboxItem{draft: draft}), do: check(draft)

  def check(%Draft{} = draft) do
    # A replacement creates nothing: the audiobook it replaces already has its
    # book, its credits and its people, and this import is about its files.
    if Replacement.replacing?(draft.replacement) do
      []
    else
      book(draft) ++
        series(draft) ++
        credits(draft, :author) ++
        set(draft) ++
        credits(draft, :narrator) ++
        people(draft)
    end
  end

  ## the book

  defp book(%Draft{work: %Work{mode: :create} = work}) do
    case Field.value(work.title) do
      title when is_binary(title) -> books_titled(title, work)
      _unsettled -> []
    end
  end

  defp book(_linked_or_absent), do: []

  defp books_titled(title, %Work{} = work) do
    key = AutoMatch.title_key(title)
    credited = credited_keys(work.authors)

    Book
    |> order_by(:id)
    |> preload(:authors)
    |> Repo.all()
    |> Enum.filter(&(AutoMatch.title_key(&1.title) == key))
    |> Enum.map(&{&1, shares_author?(&1, credited)})
    # Certain first: a twin under the same author is what this is looking
    # for, and a twin under a different one is a question about a coincidence.
    |> Enum.sort_by(fn {book, shared?} -> {!shared?, book.id} end)
    |> case do
      [] ->
        []

      books ->
        [
          %{
            kind: :book,
            section: :work,
            label: "Book: #{title}",
            certain?: Enum.any?(books, fn {_book, shared?} -> shared? end),
            matches: Enum.map(books, fn {book, _shared?} -> book_match(book) end)
          }
        ]
    end
  end

  defp book_match(%Book{} = book) do
    %{label: credit_line(book.title, book.authors), route: {:book, book.id}}
  end

  # "The Martian by Andy Weir": when one line must hold it all, the joins are
  # words.
  defp credit_line(title, []), do: title
  defp credit_line(title, authors), do: "#{title} by #{Enum.map_join(authors, ", ", & &1.name)}"

  defp shares_author?(%Book{authors: authors}, credited) do
    not MapSet.disjoint?(credited, MapSet.new(authors, &AutoMatch.person_key(&1.name)))
  end

  defp credited_keys(credits) do
    for %Credit{name: name} <- credits || [],
        is_binary(name),
        into: MapSet.new(),
        do: AutoMatch.person_key(name)
  end

  ## the series

  defp series(%Draft{work: %Work{series: links}}) do
    links |> creating() |> Enum.flat_map(&series_named/1)
  end

  defp series(_absent), do: []

  # Compared by `same_series?/2` over the whole table rather than by a key in
  # SQL, the same way `Seed` matches them: filler words are what split one
  # shelf across "X" and "X Trilogy".
  defp series_named(%SeriesLink{name: name}) do
    Series
    |> order_by(:id)
    |> Repo.all()
    |> Enum.filter(&AutoMatch.same_series?(&1.name, name))
    |> finding(:series, :work, "Series: #{name}", &%{label: &1.name, route: {:series, &1.id}})
  end

  ## the credits

  defp credits(%Draft{work: %Work{authors: credits}}, :author) do
    credits |> creating() |> Enum.flat_map(&identities_named(&1, :author))
  end

  defp credits(%Draft{recording: %{narrators: credits}}, :narrator) do
    credits |> creating() |> Enum.flat_map(&identities_named(&1, :narrator))
  end

  defp credits(_absent, _kind), do: []

  defp identities_named(%Credit{name: name}, :author) do
    Author
    |> where([a], person_key_sql(a.name) == ^AutoMatch.person_key(name))
    |> order_by(:id)
    |> preload(:people)
    |> Repo.all()
    |> finding(
      :author,
      :work,
      "Author: #{name}",
      &%{
        label: behind(&1.name, &1.people),
        route: sole_person(&1.people)
      }
    )
  end

  defp identities_named(%Credit{name: name}, :narrator) do
    Narrator
    |> where([n], person_key_sql(n.name) == ^AutoMatch.person_key(name))
    |> order_by(:id)
    |> preload(:person)
    |> Repo.all()
    |> finding(
      :narrator,
      :recording,
      "Narrator: #{name}",
      &%{
        label: behind(&1.name, List.wrap(&1.person)),
        route: sole_person(List.wrap(&1.person))
      }
    )
  end

  # A pen name says who is behind it, because that is the whole question an
  # identity collision asks: one human twice is a duplicate, while a second
  # identity backed by somebody else is two authors of one name.
  defp behind(name, []), do: name
  defp behind(name, people), do: "#{name} (#{Enum.map_join(people, " and ", & &1.name)})"

  defp sole_person([%Person{id: id}]), do: {:person, id}
  defp sole_person(_none_or_several), do: nil

  ## the people

  defp people(%Draft{people: decisions}) do
    decisions
    |> List.wrap()
    |> Enum.filter(&(&1.mode == :create))
    |> Enum.flat_map(&people_named/1)
  end

  defp people_named(%PersonDecision{} = decision) do
    case Field.value(decision.name) do
      name when is_binary(name) ->
        Person
        |> where([p], person_key_sql(p.name) == ^AutoMatch.person_key(name))
        |> order_by(:id)
        |> Repo.all()
        |> finding(
          :person,
          :people,
          "Person: #{name}",
          &%{
            label: &1.name,
            route: {:person, &1.id}
          }
        )

      _unnamed ->
        []
    end
  end

  ## the set

  # Only reachable on a book the draft links: a set belongs to a book, and a
  # book this import is about to create has none yet.
  defp set(%Draft{
         work: %Work{mode: :link, book_id: book_id},
         recording: %{recording_group: link}
       })
       when not is_nil(book_id) do
    case creating(List.wrap(link)) do
      [%GroupLink{name: name}] ->
        RecordingGroup
        |> where([g], g.book_id == ^book_id)
        |> where([g], person_key_sql(g.name) == ^AutoMatch.person_key(name))
        |> order_by(:id)
        |> Repo.all()
        |> finding(:set, :recording, "Set: #{name}", &%{label: &1.name, route: {:set, &1.id}})

      _absent_or_linked ->
        []
    end
  end

  defp set(_no_linked_book), do: []

  ## shared

  # A tombstoned row is the operator saying "not this one" and creates
  # nothing; a linked one already points at what exists.
  defp creating(rows) do
    rows
    |> List.wrap()
    |> Enum.filter(&(&1.mode == :create and not &1.removed and is_binary(&1.name)))
  end

  defp finding([], _kind, _section, _label, _match), do: []

  defp finding(rows, kind, section, label, match) do
    [
      %{
        kind: kind,
        section: section,
        label: label,
        certain?: true,
        matches: Enum.map(rows, match)
      }
    ]
  end
end
