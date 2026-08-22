defmodule Ambry.Wanted.Search do
  @moduledoc """
  Finding an audiobook to watch, across every provider that can name one.

  ## The rule is a capability, not a ranking

  **Any provider that can produce audio editions is asked, and none of them is
  preferred.** There is no primary source here and no fallback: a provider
  either can answer "which recordings of this exist" or it cannot, and the
  ones that can all get to. Nothing in this module names a provider.

  What differs between them is *shape*, not standing:

    * Some answer with recordings directly. Their search results are already
      audiobooks — narrators, runtime, cover — and nothing needs expanding.
    * Some answer with works. A novel is not a recording, so each promising
      work is expanded through `editions/2` into the audio editions it has.

  ## Why that has to be the rule rather than a preference

  Providers are differently blind about what does not exist yet, and the
  blindness does not sort into better and worse. A catalogue of what is *for
  sale* has preorders months out and forgets anything delisted. A catalogue of
  what has been *published* reaches back to tape and has no entry at all for a
  recording that has not come out. Measured: *The Velvet Knife* is findable in
  one and absent from the other; *Neuromancer*'s 1984 editions are the reverse;
  *Blightfall* is in both, under different ids, and is offered twice rather
  than merged.

  Which is exactly the import form's bargain: records are evidence, outcomes
  are visible, the operator decides. So everything comes back labelled, in the
  order the providers are configured, and nothing here scores or hides a
  candidate.

  ## Coverage this knowingly cuts

  Expanding a work costs an extra provider call, so only the first few are
  expanded — and when that truncates anything the caller is told, because a
  list that silently stopped looking reads as a list of everything there is.
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
