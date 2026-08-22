defmodule Ambry.Wanted.Search do
  @moduledoc """
  Finding a recording to watch, across every provider that can answer.

  ## Why both levels are asked, and neither is preferred

  A watch is by definition about something that has not come out yet, and the
  two provider levels know about the future in opposite ways:

    * **Recording-level providers are storefronts.** They list what they are
      *selling*, which includes preorders. Audible has *The Velvet Knife*
      (`B0FKVNLXQS`, 2026-09-29, read by Emily Ellet) months ahead.
    * **Work-level providers are bibliographies.** They catalogue what has
      been *published*, which is why they reach back to Books on Tape in 1984
      — and why Hardcover holds no audio edition of *The Velvet Knife* at all
      yet, because there isn't one to catalogue.

  Neither is the better source; they are differently blind. So both are asked
  and everything comes back labelled, in the order the providers are
  configured. Nothing here scores, ranks or hides a candidate — the operator
  chooses, exactly as they do on the import form.

  ## Work-level providers take two calls

  A work-level search answers with *works*, not recordings, so each promising
  work is expanded through `editions/2` into its audio editions. That is one
  extra provider call per work, so only the first few are expanded — and when
  that limit truncates anything, the caller is told rather than left to
  assume the list is everything.
  """

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Search
  alias Ambry.Wanted.Edition

  require Logger

  @works_expanded 3

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
    {recordings, recording_outcomes} = recording_level(query, opts)
    {editions, work_outcomes, notes} = work_level(query, opts)

    {recordings ++ editions, recording_outcomes ++ work_outcomes, notes}
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
      if :editions in entry.capabilities do
        {expanded, truncated} = expand(entry, works)
        {candidates ++ expanded, outs, notes ++ truncated}
      else
        # A provider that can find the work but cannot list its editions has
        # nothing to offer a watch. Saying so beats a silent absence.
        {candidates, outs, notes ++ [no_editions_note(entry)]}
      end
    end)
  end

  defp expand(entry, works) do
    {asked, rest} = Enum.split(works, @works_expanded)

    candidates =
      Enum.flat_map(asked, fn work ->
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

    {candidates, truncation_note(entry, rest)}
  end

  defp truncation_note(_entry, []), do: []

  defp truncation_note(entry, rest) do
    [
      "#{entry.display_name}: looked inside the first #{@works_expanded} matching books; " <>
        "#{length(rest)} more went unopened. Narrow the search to reach them."
    ]
  end

  defp no_editions_note(entry) do
    "#{entry.display_name} can find books but not their audio editions, so it offered nothing here."
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
