defmodule Ambry.Wanted.Search do
  @moduledoc """
  Finding an audiobook to watch, across every provider that can name one.

  ## Providers are selected by capability

  **Every enabled provider that can produce audio editions is asked**, in the
  registry's configured order. That is the whole selection rule: a provider is
  chosen by what it is tagged as able to do, the same way every other
  provider-driven surface here chooses one. Nothing in this module names a
  provider.

  What differs between them is *shape*:

    * Some answer with recordings directly. Their search results are already
      audiobooks — narrators, runtime, cover — and nothing needs expanding.
    * Some answer with works. A novel is not a recording, so each promising
      work is expanded through `editions/2` into the audio editions it has.

  Asking all of them matters because they disagree about what exists, in both
  directions and for structural reasons. A catalogue of what is *for sale*
  carries preorders and drops anything delisted; a catalogue of what has been
  *published* has no entry at all for a recording that has not come out yet.
  Measured: *The Velvet Knife* is findable in one and absent from the other,
  and *Blightfall* is in both under different ids — and is offered twice
  rather than merged, because they are two records of one thing and choosing
  between them is the operator's job.

  Which is the import form's bargain: records are evidence, outcomes are
  visible, the operator decides.

  ## Only what has not come out yet

  A watch is a thing to be reminded about, so a recording that is already
  published cannot be one. Candidates are filtered to a **known future
  release date** — past-dated and undated records are both dropped, since
  "no date" is not evidence of the future either.

  This is the one place that hides results, so it says how many and why. A
  search for a book whose recordings all came out years ago should read as
  *there are twelve, they are all already out*, never as *nothing found*.

  ## Every matched work is opened

  A provider that answers with works ranks them by its own idea of relevance,
  and the recording the operator wants can sit well down that list — asking
  for *Neuromancer* by William Gibson puts the actual 1984 novel sixth, behind
  a study guide and a graphic novel. So opening only the promising ones is a
  guess about precisely the thing that is uncertain.

  Instead every matched work is opened. Where a provider declares
  `:editions_bulk` that is one request for all of them; otherwise it is one
  apiece. Either way nothing is left unopened on the grounds that it looked
  unpromising.
  """

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Search
  alias Ambry.Wanted.Edition

  require Logger

  defmodule Candidate do
    @moduledoc "One recording a watch could be created from."
    defstruct [:provider, :provider_id, :edition, :published, :work_title]

    @type t :: %__MODULE__{}
  end

  @doc """
  Every recording the enabled providers can offer for this query.

  Answers `{candidates, outcomes, notes}`: the candidates in provider order,
  one outcome map per provider asked (the same vocabulary the outcome chips
  already render), and any notes about coverage this search knowingly cut.
  """
  def candidates(%Provider.Query{} = query, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())

    {recordings, recording_outcomes} = recording_level(query, opts)
    {editions, work_outcomes, notes} = work_level(query, opts)

    {upcoming, already_out} = split_by_release(recordings ++ editions, today)

    {upcoming, recording_outcomes ++ work_outcomes, notes ++ already_out_note(already_out)}
  end

  # A watch is a reminder about something that has not happened. A recording
  # that is already published cannot be one, and an undated record is not
  # evidence of the future — so both are dropped rather than offered and
  # then explained.
  defp split_by_release(candidates, today) do
    Enum.split_with(candidates, fn candidate ->
      not is_nil(candidate.published) and Date.after?(candidate.published, today)
    end)
  end

  defp already_out_note([]), do: []

  defp already_out_note(dropped) do
    {dated, undated} = Enum.split_with(dropped, & &1.published)

    [
      Enum.join(
        Enum.reject(
          [
            dated != [] && "#{length(dated)} already published",
            undated != [] && "#{length(undated)} with no announced date"
          ],
          &(&1 == false)
        ),
        ", "
      ) <> " — not shown, since a watch is for something still to come."
    ]
  end

  # A storefront's search results are already recordings; nothing to expand.
  defp recording_level(query, opts) do
    {found, outcomes} = Search.books(query, Keyword.put(opts, :level, :recording))

    candidates =
      Enum.flat_map(found, fn {entry, books} ->
        Enum.map(books, &candidate(entry.id, &1, nil))
      end)

    {candidates, outcomes}
  end

  defp work_level(query, opts) do
    {found, outcomes} = Search.books(query, Keyword.put(opts, :level, :work))

    Enum.reduce(found, {[], outcomes, []}, fn {entry, works}, {candidates, outs, notes} ->
      {expanded, entry_notes} = expand(entry, works)
      {candidates ++ expanded, outs, notes ++ entry_notes}
    end)
  end

  # Every matched work is opened, never the first few. A work-level search
  # ranks by its own idea of relevance and the recording the operator wants
  # can sit well down that list, so "open the promising ones" is a guess about
  # exactly the thing that is uncertain.
  defp expand(_entry, []), do: {[], []}

  defp expand(entry, works) do
    cond do
      :editions_bulk in entry.capabilities -> expand_bulk(entry, works)
      :editions in entry.capabilities -> expand_one_by_one(entry, works)
      # Finding the book but not its recordings leaves nothing to watch, and
      # saying so beats a silent absence.
      true -> {[], [no_editions_note(entry)]}
    end
  end

  defp expand_bulk(entry, works) do
    case Providers.editions_bulk(entry.id, Enum.map(works, & &1.id)) do
      {:ok, by_work} ->
        titles = Map.new(works, &{&1.id, &1.title})

        candidates =
          Enum.flat_map(works, fn work ->
            by_work
            |> Map.get(work.id, [])
            |> Enum.map(&candidate(entry.id, &1, titles[work.id]))
          end)

        {candidates, []}

      other ->
        Logger.warning(fn -> "Wanted search: #{entry.id} bulk editions: #{inspect(other)}" end)

        {[], [could_not_open_note(entry)]}
    end
  end

  defp expand_one_by_one(entry, works) do
    candidates =
      Enum.flat_map(works, fn work ->
        case Providers.editions(entry.id, work.id) do
          {:ok, editions} ->
            Enum.map(editions, &candidate(entry.id, &1, work.title))

          other ->
            Logger.warning(fn ->
              "Wanted search: #{entry.id} editions for #{work.id}: #{inspect(other)}"
            end)

            []
        end
      end)

    {candidates, []}
  end

  defp no_editions_note(entry) do
    "#{entry.display_name} can find books but not their audio editions, so it offered nothing here."
  end

  defp could_not_open_note(entry) do
    "#{entry.display_name} found books but could not be asked what recordings they have."
  end

  defp candidate(provider_id, book, work_title) do
    %Candidate{
      provider: provider_id,
      provider_id: book.id,
      edition: Edition.from_provider_book(book),
      published: published_date(book),
      work_title: work_title
    }
  end

  defp published_date(%{published: %{date: %Date{} = date}}), do: date
  defp published_date(_book), do: nil
end
