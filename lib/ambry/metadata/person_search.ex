defmodule Ambry.Metadata.PersonSearch do
  @moduledoc """
  Everything every provider knows about a human, gathered for a picker.

  One photo per provider is the right shape for "give me a face" and the wrong
  shape for the job an operator has, which is finding a photo that survives a
  **circular crop**. The obvious portrait is frequently the one that doesn't.

  So this widens on both axes:

    * **several people per provider**, because searching a name can return
      more than one human and only the operator can tell which is theirs;
    * **several photos per person**, because a photo database keeps every
      headshot anyone uploaded and an encyclopedia has both a lead image and
      a portrait.

  Bios come back the same way: a lead paragraph, a biography and an author
  blurb are three different texts about one person, and which one belongs in
  the library is a judgement.
  """

  alias Ambry.Metadata.Outcome
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  require Logger

  # How many search hits per provider are worth a details call. Past a few,
  # a name search is returning people who merely share a word.
  @hits 3

  defmodule Match do
    @moduledoc "One person a provider believes it found, with everything it has."

    defstruct [:provider_id, :provider_name, :id, :name, :description, :note, images: []]

    @type t :: %__MODULE__{}
  end

  @doc """
  The providers that can be asked about a person.
  """
  def providers, do: Registry.enabled(capability: :author_search)

  @doc """
  Everything one provider has on people matching `query`.

  Never raises and never returns an error: down, rate limited and "nobody by
  that name" all mean the same thing to the grid.
  """
  def matches(entry, query, opts \\ []) do
    {matches, _outcome} = matches_with_outcome(entry, query, opts)
    matches
  end

  @doc """
  The same search, plus what the provider actually did — one outcome per kind
  of call it took.

  The picker doesn't care, but matching runs unattended and has to tell
  "found nobody" from "was unreachable" afterwards.

  Two calls, so up to two outcomes. A successful name search is followed by a
  details call per plausible hit, and that call is where the biography and
  the headshots are. A hit with no photo and no bio is dropped from the grid,
  so a rate-limited details call deletes the person entirely. Reported under
  its own `:details` id, which is what makes `Ambry.Inbox.RunMatch` come back
  for it.
  """
  def matches_with_outcome(entry, query, opts \\ []) do
    case Providers.search_authors(entry.id, query, opts) do
      {:ok, results} ->
        {hydrated, errors} =
          results
          |> Enum.filter(&plausible?(query, &1.name))
          |> Enum.take(@hits)
          |> Enum.map_reduce([], fn summary, errors ->
            case hydrate(entry, summary, opts) do
              {match, nil} -> {match, errors}
              {match, reason} -> {match, [reason | errors]}
            end
          end)

        matches = Enum.reject(hydrated, &(&1.images == [] and is_nil(&1.description)))

        {matches, [Outcome.ok(entry, length(matches)) | details_outcome(entry, errors)]}

      {:error, reason} ->
        Logger.info(fn ->
          "Person search: #{entry.id} for #{inspect(query)}: #{inspect(reason)}"
        end)

        {[], List.wrap(Outcome.from_error(entry, reason))}
    end
  end

  defp details_outcome(_entry, []), do: []

  defp details_outcome(entry, [reason | _rest]),
    do: List.wrap(Outcome.from_error(entry, reason, :details))

  # The search hit is a summary; the details call is where the biography and
  # the headshots live. Returns the reason alongside, because a hit that
  # failed to hydrate and one the provider knows nothing more about produce
  # the same thin `Match`.
  defp hydrate(entry, %Provider.Author{} = summary, opts) do
    {detailed, error} =
      case Providers.author_details(entry.id, summary.id, opts) do
        {:ok, %Provider.Author{} = full} -> {full, nil}
        {:error, reason} -> {summary, reason}
        _no_details -> {summary, nil}
      end

    {%Match{
       provider_id: entry.id,
       provider_name: entry.display_name,
       id: summary.id,
       name: detailed.name || summary.name,
       description: detailed.description || summary.description,
       # The search listing's description doubles as a disambiguator, which
       # is what tells two same-named people apart in a grid.
       note: summary.description,
       images: Enum.uniq(Provider.Author.images(detailed) ++ Provider.Author.images(summary))
     }, error}
  end

  # Guards against confidently-wrong candidates: a book-relevance-driven
  # author search can surface the book's author when asked about a narrator.
  # Jaro distance can't separate that from a legitimate name variant, but
  # sharing a name token does.
  defp plausible?(query, name) do
    not MapSet.disjoint?(tokens(query), tokens(name))
  end

  defp tokens(nil), do: MapSet.new()

  defp tokens(string) do
    string
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 2))
    |> MapSet.new()
  end
end
