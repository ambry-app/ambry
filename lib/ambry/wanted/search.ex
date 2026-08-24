defmodule Ambry.Wanted.Search do
  @moduledoc """
  Finding an audiobook to watch, across every provider that can name one.

  **A provider is asked when it can produce audio editions**, in the
  registry's configured order. That is the whole selection rule; nothing here
  names a provider. Finding the book is not finding an audiobook, so a
  work-level provider that cannot then say which recordings a work has is not
  asked at all — it would cost a request and contribute nothing.

  What differs between the ones that are asked is shape. Some answer with
  recordings directly, and nothing needs expanding. Some answer with works,
  so each is expanded through `editions/2` into the audio editions it has.

  Asking all of them matters because they disagree about what exists, in both
  directions: a catalogue of what is *for sale* carries preorders and drops
  anything delisted, while a catalogue of what has been *published* has no
  entry for a recording that has not come out yet. A recording both hold is
  offered twice rather than merged.

  Candidates come back mixed and ranked by `Ambry.Inbox.score_records/3`, the
  scorer matching already uses. Which database answered rides on the record as
  a badge; grouping by it would rank every provider's best guess against a
  different scale.

  Only what has not come out yet: a watch is a thing to be reminded about, so
  candidates are filtered to a known future release date, and undated records
  go too. This is the one place that hides results, so it says how many, and
  it is the only thing the notes are for. A provider in trouble reports an
  `Ambry.Metadata.Outcome` under its own kind, the way every other provider
  call in the app does.

  Every matched work is opened, never the first few: a work-level search ranks
  by its own idea of relevance and the recording the operator wants can sit
  well down that list. Where a provider declares `:editions_bulk` that is one
  request for all of them, otherwise one apiece.
  """

  alias Ambry.Inbox
  alias Ambry.Metadata.Outcome
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry
  alias Ambry.Metadata.Search
  alias Ambry.Wanted.Edition

  require Logger

  defmodule Candidate do
    @moduledoc "One recording a watch could be created from."
    defstruct [:provider, :provider_id, :edition, :published, :work_title, :score]

    @type t :: %__MODULE__{}
  end

  @doc """
  Every recording the enabled providers can offer for this query.

  Answers `{candidates, outcomes, notes}`: candidates best first whoever
  found them, one outcome map per provider asked, and any notes about what
  was found and not shown.
  """
  def candidates(%Provider.Query{} = query, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())

    hints =
      Inbox.form_hints(%{title: query.title, author: query.author, narrator: query.narrator})

    {recordings, recording_outcomes} = recording_level(query, hints, opts)
    {editions, work_outcomes} = work_level(query, hints, opts)

    {upcoming, already_out} = split_by_release(recordings ++ editions, today)

    {rank(upcoming), recording_outcomes ++ work_outcomes, already_out_note(already_out)}
  end

  # Best first, ties in the order the providers were asked: a stable sort is
  # what keeps two searches for one thing from reshuffling.
  defp rank(candidates), do: Enum.sort_by(candidates, & &1.score, :desc)

  # A watch is a reminder about something that has not happened, and an
  # undated record is not evidence of the future.
  defp split_by_release(candidates, today) do
    Enum.split_with(candidates, fn candidate ->
      not is_nil(candidate.published) and Date.after?(candidate.published, today)
    end)
  end

  defp already_out_note([]), do: []

  defp already_out_note(dropped) do
    {dated, undated} = Enum.split_with(dropped, & &1.published)

    [
      [
        dated != [] && "#{length(dated)} already released",
        undated != [] && "#{length(undated)} with no date"
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(", ")
      |> Kernel.<>(" not shown.")
    ]
  end

  # A storefront's search results are already recordings; nothing to expand.
  defp recording_level(query, hints, opts) do
    {found, outcomes} = Search.books(query, Keyword.put(opts, :level, :recording))

    candidates =
      Enum.flat_map(found, fn {entry, books} ->
        Enum.map(books, &candidate(entry, &1, nil, hints))
      end)

    {candidates, outcomes}
  end

  defp work_level(query, hints, opts) do
    Enum.reduce(edition_capable(), {[], []}, fn entry, {candidates, outcomes} ->
      {works, searched} = Search.books_one(entry, query, opts)
      {expanded, opened} = expand(entry, works, hints)

      {candidates ++ expanded, outcomes ++ List.wrap(searched) ++ opened}
    end)
  end

  # Selected before anything is asked, rather than after: a provider that
  # finds the book and cannot say which recordings it has has nothing to
  # offer a watch, and asking it anyway spends a request to earn a line
  # apologising for itself.
  defp edition_capable do
    [level: :work, capability: :book_search]
    |> Registry.enabled()
    |> Enum.filter(
      &Enum.any?(&1.capabilities, fn capability ->
        capability in [:editions, :editions_bulk]
      end)
    )
  end

  # Every matched work is opened, never the first few: "open the promising
  # ones" is a guess about exactly the thing that is uncertain.
  defp expand(_entry, [], _hints), do: {[], []}

  defp expand(entry, works, hints) do
    if :editions_bulk in entry.capabilities,
      do: expand_bulk(entry, works, hints),
      else: expand_one_by_one(entry, works, hints)
  end

  defp expand_bulk(entry, works, hints) do
    case Providers.editions_bulk(entry.id, Enum.map(works, & &1.id)) do
      {:ok, by_work} ->
        titles = Map.new(works, &{&1.id, &1.title})

        candidates =
          Enum.flat_map(works, fn work ->
            by_work
            |> Map.get(work.id, [])
            |> Enum.map(&candidate(entry, &1, titles[work.id], hints))
          end)

        {candidates, opened_outcome(entry, candidates, [])}

      other ->
        Logger.warning(fn -> "Wanted search: #{entry.id} bulk editions: #{inspect(other)}" end)

        {[], opened_outcome(entry, [], [reason(other)])}
    end
  end

  defp expand_one_by_one(entry, works, hints) do
    {candidates, failures} =
      Enum.reduce(works, {[], []}, fn work, {candidates, failures} ->
        case Providers.editions(entry.id, work.id) do
          {:ok, editions} ->
            {candidates ++ Enum.map(editions, &candidate(entry, &1, work.title, hints)), failures}

          other ->
            Logger.warning(fn ->
              "Wanted search: #{entry.id} editions for #{work.id}: #{inspect(other)}"
            end)

            {candidates, failures ++ [reason(other)]}
        end
      end)

    {candidates, opened_outcome(entry, candidates, failures)}
  end

  # One chip for however many calls it took to open the works, and a failure
  # outranks an answer: a provider rate-limited on one work of five otherwise
  # reports a clean count, and the recordings it never got are never
  # mentioned. The same rule every other post-search call in the app follows.
  defp opened_outcome(entry, candidates, []),
    do: List.wrap(Outcome.ok(entry, length(candidates), :editions))

  defp opened_outcome(entry, _candidates, [reason | _rest]),
    do: List.wrap(Outcome.from_error(entry, reason, :editions))

  defp reason({:error, reason}), do: reason
  defp reason(other), do: other

  # Scored through matching's own scorer rather than a second one written
  # here, or the same evidence is ranked two ways on two pages.
  defp candidate(entry, book, work_title, hints) do
    %{"score" => score} = book |> List.wrap() |> Inbox.score_records(entry, hints) |> hd()

    %Candidate{
      provider: entry.id,
      provider_id: book.id,
      edition: Edition.from_provider_book(book),
      published: published_date(book),
      work_title: work_title,
      score: score
    }
  end

  defp published_date(%{published: %{date: %Date{} = date}}), do: date
  defp published_date(_book), do: nil
end
