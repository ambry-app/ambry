defmodule Ambry.Metadata.Search do
  @moduledoc """
  The multi-provider fan-out: ask every enabled, capable provider one
  question, and report per-provider what came back — including from the ones
  that couldn't answer.

  This is the searching half of what `Ambry.Inbox.Lookup` used to do, pulled
  down to the metadata layer because it was never inbox-specific: the same
  "search all providers once, records are evidence, outcomes are visible"
  paradigm is what the legacy book/person/media forms converge on, and they
  can't reach inbox internals (nor should they — nothing here knows what an
  inbox item is).

  Two invariants every caller relies on:

    * **Askers learn who was asked.** Results come paired with an outcome per
      provider (`"ok"` with a count, or `"failed"` with a reason), because
      "found nothing" and "was unreachable" have to be told apart afterwards.
      The outcome maps are the shared vocabulary the outcome chips render.

    * **This layer only asks.** Scoring, normalization against local hints,
      and persistence belong to the caller — matching scores against an
      item's tags, a form might not score at all.
  """

  alias Ambry.Metadata.Outcome
  alias Ambry.Metadata.PersonSearch
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  require Logger

  @doc """
  Asks every enabled provider capable of book search at the given level.

  Returns `{found, outcomes}` where `found` is a list of `{registry_entry,
  books}` pairs — callers normalize per entry — and `outcomes` is one status
  map per provider asked.
  """
  def books(%Provider.Query{} = query, opts) do
    level = Keyword.fetch!(opts, :level)

    [level: level, capability: :book_search]
    |> Registry.enabled()
    |> Enum.reduce({[], []}, fn entry, {found, outcomes} ->
      {books, outcome} = books_one(entry, query, opts)
      {found ++ [{entry, books}], outcomes ++ [outcome]}
    end)
  end

  @doc """
  Asks one provider — the retry path for the one that was rate-limited or
  down when everyone else answered.
  """
  def books_one(entry, %Provider.Query{} = query, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, true)

    case Providers.search_books(entry.id, query, refresh: refresh) do
      {:ok, books} ->
        {books, ok_outcome(entry, length(books))}

      {:error, reason} ->
        Logger.warning(fn -> "Metadata search: #{entry.id} failed: #{inspect(reason)}" end)
        {[], failed_outcome(entry, reason)}
    end
  end

  @doc """
  Asks every person-capable provider about one human.

  Returns `{matches, outcomes}` — flat `PersonSearch` matches across
  providers, plus the same per-provider outcome maps as `books/2`. A provider
  contributes more than one outcome when more than one kind of call was
  needed to answer: the search, and the details behind each hit.
  """
  def people(name, opts \\ []) do
    Enum.reduce(PersonSearch.providers(), {[], []}, fn entry, {found, outcomes} ->
      {matches, provider_outcomes} =
        PersonSearch.matches_with_outcome(entry, name, refresh: Keyword.get(opts, :refresh, true))

      {found ++ matches, outcomes ++ provider_outcomes}
    end)
  end

  @doc """
  Asks every enabled provider capable of chapter lists about one recording,
  by ASIN — the recording-level natural key, which is why the caller hands
  one in rather than a query: chapter lists exist per retail edition, not
  per work.

  Returns `{found, outcomes}` where `found` is a list of `{registry_entry,
  %Provider.Chapters{}}` pairs. Only ever a *title* source — provider
  timestamps describe the provider's own edition and are never applied to a
  timeline (roadmap 1h).
  """
  def chapters(asin, opts \\ []) do
    refresh = Keyword.get(opts, :refresh, true)

    [capability: :chapters]
    |> Registry.enabled()
    |> Enum.reduce({[], []}, fn entry, {found, outcomes} ->
      case Providers.chapters(entry.id, asin, refresh: refresh) do
        {:ok, %Provider.Chapters{} = chapters} ->
          {found ++ [{entry, chapters}],
           outcomes ++ [ok_outcome(entry, length(chapters.chapters))]}

        {:error, reason} ->
          Logger.warning(fn -> "Metadata chapters: #{entry.id} failed: #{inspect(reason)}" end)
          {found, outcomes ++ [failed_outcome(entry, reason)]}
      end
    end)
  end

  defp ok_outcome(entry, count), do: Outcome.ok(entry, count)

  defp failed_outcome(entry, reason), do: Outcome.failed(entry, reason)
end
