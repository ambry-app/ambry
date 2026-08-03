defmodule Ambry.Inbox.Draft.Seed do
  @moduledoc """
  Builds a draft from what an item's files and providers had to say.

  Seeding is where the auto-approval rules live. Their shared logic: a rule
  may only settle a decision when getting it wrong would be *cheap* — either
  because the answer is identity rather than similarity (an ASIN, an exact
  name match), or because there was only ever one answer on offer. Everything
  else is left for a human, because the inbox exists precisely for the cases
  automation gets wrong.

  ## The rules

    * **work identity** — auto on ASIN identity, an exact local title+author
      match, or a top score ≥ 0.90 whose runner-up is ≤ 0.70. Local books
      already outrank equal provider hits in `AutoMatch`, so "reuse the work"
      wins by default.
    * **scalar** — nothing proposed and optional: waived. One proposal: taken.
      Several that agree once normalized: taken. Several that disagree:
      the operator's.
    * **credit** — one exact identity match: linked. No match at all, name
      from a provider-matched work: created 1:1. A *Person* matches but the
      identity doesn't: always the operator's, because "is this the same
      human?" is exactly the judgment not to automate.
    * **new credit from tags, never automatically** — tag names come from the
      multi-value splitting 1b calls knowingly imperfect ("Sanderson,
      Brandon"). This is the rule that stops the inbox quietly filling the
      library with malformed people.
    * **series number** — never invented. Only a number an actual source
      supplied can settle it.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Candidate
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  @strong_match 0.90
  @weak_runner_up 0.70

  @doc """
  Builds a fresh draft for an item from its matches, tags and release name.
  """
  def build(%InboxItem{} = item) do
    hints = AutoMatch.hints(item)
    tags = item.tags || %{}
    matches = item.matches || %{}

    work_level = Map.get(matches, "work", %{})
    recording_level = Map.get(matches, "recording", %{})

    %Draft{
      evidence: evidence(item),
      stale: false,
      work: work(work_level, hints, tags),
      recording: recording(recording_level, hints, tags, item)
    }
  end

  @doc """
  Marks a draft as built against evidence that has since changed.

  Discovery must never rewrite a curated choice, so a file that moved or was
  replaced makes the draft *say so* rather than silently re-seeding over the
  operator's work.
  """
  def restale(nil, _item), do: nil

  def restale(%Draft{} = draft, %InboxItem{} = item) do
    %{draft | stale: draft.evidence != evidence(item)}
  end

  # Cheap and sufficient: what a draft was built against is the set of files
  # and their probe. Neither a rename nor a replacement can slip past it.
  defp evidence(%InboxItem{} = item) do
    :erlang.phash2({item.files, item.probe}) |> Integer.to_string()
  end

  ## work

  defp work(level, hints, tags) do
    candidates = Map.get(level, "candidates", []) || []
    best = List.first(candidates)
    confidence = Map.get(level, "confidence")

    {mode, book_id, approved} = work_identity(candidates, confidence)

    %Work{
      mode: mode,
      book_id: book_id,
      approved: approved,
      candidates: candidates,
      confidence: confidence,
      query: Map.get(level, "query"),
      title: title_field(best, hints, tags),
      published: published_field(best, tags),
      published_format: published_format_field(best, tags),
      authors: author_credits(best, tags),
      series: series_links(best, tags, book_id)
    }
  end

  # An existing Book is the best outcome there is — it's what stops a second
  # recording of a work splitting the library — so a confident local hit links
  # rather than creating a near-duplicate.
  defp work_identity([], _confidence), do: {:create, nil, false}

  defp work_identity([best | rest], confidence) do
    strong? = strong?(best, rest, confidence)

    case best do
      %{"source" => "local", "id" => id} when is_integer(id) -> {:link, id, strong?}
      _provider -> {:create, nil, strong?}
    end
  end

  defp strong?(best, rest, confidence) do
    runner_up = rest |> List.first() |> then(&(&1 && &1["score"])) || 0.0

    cond do
      best["score"] == 1.0 -> true
      (confidence || 0.0) >= @strong_match and runner_up <= @weak_runner_up -> true
      true -> false
    end
  end

  # The release name is a fallback, not a peer. Measured across the real
  # library, 96% of releases carry a title in tags and the parser is what the
  # other ~2% rely on — so letting the folder name argue with a provider would
  # make nearly every import ambiguous on its title for no gain.
  defp title_field(best, hints, tags) do
    [candidate(best, "title"), tag_candidate(tags, "book_title")]
    |> scalar(required: true, fallback: release_candidate(hints.title))
  end

  defp published_field(best, tags) do
    [candidate(best, "published"), tag_candidate(tags, "published")]
    |> scalar(required: true)
  end

  # Not derivable from the date: year-only knowledge arrives as a literal
  # Jan 1st, and rendering that as a real release day is the exact bug the
  # v1.9.0 punch list fixed for the import forms.
  defp published_format_field(best, tags) do
    [candidate(best, "published_format"), tag_candidate(tags, "published_format")]
    |> scalar(required: false)
    |> default_to("full")
  end

  defp default_to(%Field{value: nil, candidates: []} = field, value) do
    %{field | value: value, source: "default", approved: true}
  end

  defp default_to(field, _value), do: field

  ## recording

  defp recording(level, _hints, tags, item) do
    candidates = Map.get(level, "candidates", []) || []
    best = List.first(candidates)

    %Recording{
      candidates: candidates,
      confidence: Map.get(level, "confidence"),
      query: Map.get(level, "query"),
      # A new recording is what an inbox item almost always is, and the
      # skeleton has no other option to offer — so the identity is settled by
      # construction. Replace-an-existing-recording is the option this grows.
      approved: true,
      title: [] |> scalar(required: false),
      published: [candidate(best, "published")] |> scalar(required: false),
      publisher: [candidate(best, "publisher"), tag_candidate(tags, "publisher")] |> scalar(),
      description:
        [candidate(best, "description"), tag_candidate(tags, "description")] |> scalar(),
      cover: cover_field(best, tags, item),
      narrators: narrator_credits(best, tags)
    }
  end

  # Embedded art and a provider cover are both real answers, so two of them is
  # a choice rather than a winner. The embedded candidate carries the audio
  # file to extract from; approval does the extracting.
  defp cover_field(best, tags, item) do
    embedded =
      if tags["has_cover_art"] && item.files != [] do
        %Candidate{
          value: List.first(item.files),
          source: "embedded",
          label: "Embedded in the file"
        }
      end

    [candidate(best, "cover_url"), embedded] |> scalar(required: false)
  end

  ## credits

  defp author_credits(best, tags) do
    names = names(best && best["authors"]) || names(tags["authors"]) || []
    source = if names == names(best && best["authors"]), do: source_of(best), else: "tags"

    Enum.map(names, &credit(&1, :author, source))
  end

  defp narrator_credits(best, tags) do
    names = names(best && best["narrators"]) || names(tags["narrators"]) || []
    source = if names == names(best && best["narrators"]), do: source_of(best), else: "tags"

    Enum.map(names, &credit(&1, :narrator, source))
  end

  defp credit(name, kind, source) do
    matches = identity_matches(name, kind)
    people = person_matches(name)

    base = %Credit{name: name, kind: kind, source: source, candidates: matches}

    case {matches, people} do
      # exactly one existing identity by that name — link it and move on
      {[%{exact: true} = match], _people} ->
        %{base | mode: :link, identity_id: match.identity_id, approved: true}

      # nobody by that name at all: create it, backed by one new person.
      # Auto only when a provider-matched work supplied the name — tag names
      # are split by a knowingly imperfect rule.
      {[], []} ->
        %{
          base
          | mode: :create,
            people: Credit.new_person_default(name),
            approved: provider?(source)
        }

      # a Person exists but this identity doesn't — "is this the same human?"
      # is never automated
      {[], _people} ->
        %{base | mode: :create, people: Credit.new_person_default(name), approved: false}

      # more than one identity shares this name; two people really can
      {_several, _people} ->
        %{base | mode: :create, people: Credit.new_person_default(name), approved: false}
    end
  end

  defp identity_matches(name, :author) do
    Author
    |> where([a], fragment("lower(?)", a.name) == ^String.downcase(name))
    |> preload(:people)
    |> Repo.all()
    |> Enum.map(fn author ->
      %Credit.Match{
        identity_id: author.id,
        name: author.name,
        people: author.people |> Enum.map_join(" and ", & &1.name) |> presence(),
        exact: true
      }
    end)
  end

  defp identity_matches(name, :narrator) do
    Narrator
    |> where([n], fragment("lower(?)", n.name) == ^String.downcase(name))
    |> preload(:person)
    |> Repo.all()
    |> Enum.map(fn narrator ->
      %Credit.Match{
        identity_id: narrator.id,
        name: narrator.name,
        people: narrator.person && narrator.person.name,
        exact: true
      }
    end)
  end

  defp person_matches(name) do
    Person
    |> where([p], fragment("lower(?)", p.name) == ^String.downcase(name))
    |> Repo.all()
  end

  ## series

  # When linking to an existing book, a proposed series is only offered if the
  # book doesn't already have it: an import may fill a blank, never overwrite
  # curation.
  defp series_links(best, tags, book_id) do
    names = names(best && best["series"]) || names(tags["series"]) || []
    number = tags["series_number"]
    source = if names == names(best && best["series"]), do: source_of(best), else: "tags"

    names
    |> Enum.reject(&already_on_book?(&1, book_id))
    |> Enum.map(&series_link(&1, number, source))
  end

  defp already_on_book?(_name, nil), do: false

  defp already_on_book?(name, book_id) do
    Book
    |> where([b], b.id == ^book_id)
    |> join(:inner, [b], sb in assoc(b, :series_books))
    |> join(:inner, [_b, sb], s in assoc(sb, :series))
    |> where([_b, _sb, s], fragment("lower(?)", s.name) == ^String.downcase(name))
    |> Repo.exists?()
  end

  defp series_link(name, number, source) do
    matches =
      Series
      |> where([s], fragment("lower(?)", s.name) == ^String.downcase(name))
      |> Repo.all()
      |> Enum.map(&%SeriesLink.Match{series_id: &1.id, name: &1.name, exact: true})

    base = %SeriesLink{name: name, number: presence(number), source: source, candidates: matches}

    case matches do
      # A number nobody supplied is a question, not a default. Getting this
      # wrong writes confident nonsense into a curated field.
      _any when number in [nil, ""] ->
        %{base | mode: mode_for(matches), series_id: series_id(matches), approved: false}

      [one] ->
        %{base | mode: :link, series_id: one.series_id, approved: true}

      [] ->
        %{base | mode: :create, approved: provider?(source)}

      _several ->
        %{base | mode: :create, approved: false}
    end
  end

  defp mode_for([_one]), do: :link
  defp mode_for(_other), do: :create

  defp series_id([one]), do: one.series_id
  defp series_id(_other), do: nil

  ## scalars

  # `fallback` is a weaker source that only gets a say when the primary ones
  # said nothing — it never argues with them, and never turns a settled field
  # into a choice.
  defp scalar(candidates, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    candidates = Enum.reject(candidates, &is_nil/1)

    candidates =
      case {distinct(candidates), Keyword.get(opts, :fallback)} do
        {[], fallback} when not is_nil(fallback) -> [fallback]
        _primary_had_something -> candidates
      end

    field = %Field{required: required, candidates: candidates}

    case distinct(candidates) do
      # nothing proposed it. Optional means waived — an explicit "none", which
      # is what makes "every piece resolved" reachable at all.
      [] ->
        %{field | approved: not required}

      # one answer, whether from one source or several that agree
      [value] ->
        %{field | value: value, source: source_for(candidates, value), approved: true}

      _several ->
        %{field | approved: false}
    end
  end

  defp distinct(candidates) do
    candidates
    |> Enum.map(& &1.value)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq_by(&normalize/1)
  end

  defp source_for(candidates, value) do
    Enum.find_value(candidates, fn candidate ->
      candidate.value == value && candidate.source
    end)
  end

  defp normalize(string) when is_binary(string) do
    string |> String.downcase() |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  defp normalize(other), do: other

  ## candidate helpers

  defp candidate(nil, _key), do: nil

  defp candidate(best, key) do
    case presence(best[key]) do
      nil -> nil
      value -> %Candidate{value: to_string(value), source: source_of(best), label: label_of(best)}
    end
  end

  defp tag_candidate(tags, key) do
    case presence(tags[key]) do
      nil -> nil
      value -> %Candidate{value: to_string(value), source: "tags", label: "The file's tags"}
    end
  end

  defp release_candidate(nil), do: nil

  defp release_candidate(value),
    do: %Candidate{value: value, source: "release_name", label: "The release name"}

  defp source_of(nil), do: nil
  defp source_of(%{"source" => source}), do: source
  defp source_of(_other), do: nil

  defp label_of(%{"provider_name" => name}) when is_binary(name), do: name
  defp label_of(%{"source" => "local"}), do: "Already in the library"
  defp label_of(%{"source" => source}), do: source
  defp label_of(_other), do: nil

  defp provider?("provider:" <> _rest), do: true
  defp provider?(_other), do: false

  defp names(nil), do: nil
  defp names([]), do: nil
  defp names(list) when is_list(list), do: list |> Enum.map(&presence/1) |> Enum.reject(&is_nil/1)
  defp names(value) when is_binary(value), do: [value]
  defp names(_other), do: nil

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(other), do: other
end
