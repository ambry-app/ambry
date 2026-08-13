defmodule Ambry.Metadata.PersonSearch do
  @moduledoc """
  Everything every provider knows about a human, gathered for a picker.

  The person form's original picker took **one photo from each provider** —
  the top search hit's primary image. That is the right shape for "give me a
  face" and the wrong shape for the job an operator actually has, which is
  finding a photo that survives a **circular crop**. The obvious portrait is
  frequently the one that doesn't: a head at the edge of a wide shot, a group
  photo, a book jacket with the face bottom-left. What's needed is
  alternatives.

  So this widens on both axes:

    * **several people per provider**, because searching a name can return
      more than one human and only the operator can tell which is theirs;
    * **several photos per person**, because TMDB keeps every headshot anyone
      uploaded and Wikipedia has both an article lead image and a Commons
      portrait — often different pictures.

  Bios come back the same way. Wikipedia's lead paragraph, TMDB's biography
  and a book database's author blurb are three different texts about one
  person, and which one belongs in the library is a judgement.
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

  Never raises and never returns an error: a provider that is down, rate
  limited or simply has nobody by that name all mean the same thing to the
  operator looking at the grid — no photos from that column.
  """
  def matches(entry, query, opts \\ []) do
    {matches, _outcome} = matches_with_outcome(entry, query, opts)
    matches
  end

  @doc """
  The same search, plus what the provider actually did — one outcome per kind
  of call it took.

  The picker doesn't care — an operator staring at an empty column has the
  same problem whether the provider was down or simply had nobody. Matching
  does: it runs unattended, and "this provider found nobody" and "this
  provider was unreachable" have to be told apart afterwards, which is the
  same rule the work and recording levels already follow.

  **Two calls, so up to two outcomes.** A name search that succeeds is
  followed by a details call per plausible hit, and that call is where the
  biography and the headshots are. Measured on a cold scan of 353 releases,
  the shared rreading-glasses instance 429'd about 6% of requests — and
  because a hit with no photo and no bio is dropped from the grid on the very
  next line, a rate-limited details call didn't just thin the candidate, it
  **deleted the person** while this function still reported `ok`. So a details
  failure is reported under its own `:details` id, which is what makes
  `Ambry.Inbox.RunMatch` come back for it.
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

        {[], [Outcome.failed(entry, reason)]}
    end
  end

  defp details_outcome(_entry, []), do: []
  defp details_outcome(entry, [reason | _rest]), do: [Outcome.failed(entry, reason, :details)]

  # The search hit is a summary; the details call is where the biography and
  # the full set of headshots live. Worth one request per plausible hit — this
  # runs for a single person with somebody waiting on it, not across a scan.
  #
  # Returns the reason alongside, because a hit that failed to hydrate and a
  # hit the provider genuinely knows nothing more about produce the same
  # thin `Match` and must not be reported the same way.
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
       # The search listing's description doubles as a disambiguator on TMDB
       # ("Acting — The Expanse"), which is exactly what tells two same-named
       # people apart in a grid.
       note: summary.description,
       images: Enum.uniq(Provider.Author.images(detailed) ++ Provider.Author.images(summary))
     }, error}
  end

  # Guards against confidently-wrong candidates: rreading-glasses' author
  # search is book-relevance driven, so searching a narrator can surface the
  # book's *author* instead (Jefferson Mays → James S.A. Corey). Jaro distance
  # can't separate that from a legitimate name variant ("Ty Franck" vs "Tyler
  # Corey Franck" scores lower than the Corey mismatch) — but sharing a name
  # token does.
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
