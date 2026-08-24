defmodule Ambry.Metadata.Providers.Wikidata do
  @moduledoc """
  Person-level provider backed by Wikidata, Wikipedia and Wikimedia Commons.

  The anchor of the person level: keyed on *real people* rather than
  published-as author identities. Book-catalog providers cannot see people who
  barely exist as catalog authors, such as half of a composite pen name or a
  narrate-only person, while Wikidata models the humans themselves.

  Wikidata entity search, hydrated and filtered to humans (P31 = Q5), then a
  bio from the Wikipedia summary-extract API (falling back to the terse
  Wikidata description), then a freely-licensed photo, preferring the
  summary's direct `originalimage` URL over the Commons P18 claim via
  Special:FilePath.

  Zero-config and free, no API key.

  """

  @behaviour Ambry.Metadata.Provider

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.Wikidata.Client

  @wikidata_api "https://www.wikidata.org/w/api.php"
  @wikipedia_summary_url "https://en.wikipedia.org/api/rest_v1/page/summary/"
  @commons_file_path_url "https://commons.wikimedia.org/wiki/Special:FilePath/"

  # Commons originals can be tens of MB; Special:FilePath scales server-side,
  # and 1200px is plenty for the thumbnail pipeline.
  @image_width 1200

  @search_limit 10
  @human "Q5"

  @impl Provider
  def id, do: "wikidata"

  @impl Provider
  def display_name, do: "Wikipedia"

  @impl Provider
  def level, do: :person

  @impl Provider
  def capabilities, do: [:author_search, :author_details]

  @impl Provider
  def config_fields, do: []

  @impl Provider
  def search_authors(query, _config) do
    with {:ok, results} <- search_entities(query) do
      results |> Enum.map(& &1["id"]) |> hydrate_people()
    end
  end

  @impl Provider
  def author_details(qid, _config) do
    with {:ok, entities} <- get_entities([qid], "claims|labels|descriptions|sitelinks") do
      case entities[qid] do
        %{"missing" => _missing} -> {:error, :not_found}
        nil -> {:error, :not_found}
        entity -> {:ok, entity_details(entity)}
      end
    end
  end

  defp search_entities(query) do
    params = [
      action: "wbsearchentities",
      search: query,
      language: "en",
      uselang: "en",
      type: "item",
      limit: @search_limit,
      format: "json"
    ]

    case Client.get_json(@wikidata_api, params) do
      {:ok, %{"search" => results}} -> {:ok, results}
      {:ok, _other} -> {:error, :unexpected_response_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_entities(ids, props) do
    params = [
      action: "wbgetentities",
      ids: Enum.join(ids, "|"),
      props: props,
      languages: "en",
      sitefilter: "enwiki",
      format: "json"
    ]

    case Client.get_json(@wikidata_api, params) do
      {:ok, %{"entities" => entities}} -> {:ok, entities}
      {:ok, _other} -> {:error, :unexpected_response_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  # Entity search matches organizations, works and disambiguation pages too,
  # so the hits' claims are hydrated to keep only humans.
  defp hydrate_people([]), do: {:ok, []}

  defp hydrate_people(ids) do
    with {:ok, entities} <- get_entities(ids, "claims|labels|descriptions") do
      {:ok,
       ids
       |> Enum.map(&entities[&1])
       |> Enum.filter(&human?/1)
       |> Enum.map(&entity_summary/1)}
    end
  end

  defp human?(nil), do: false

  defp human?(entity) do
    entity
    |> claim_values("P31")
    |> Enum.any?(&match?(%{"id" => @human}, &1))
  end

  # search listing: name + the terse Wikidata description ("American
  # science fiction author") is enough to pick the right person
  defp entity_summary(entity) do
    %Provider.Author{
      provider: id(),
      id: entity["id"],
      name: label(entity),
      description: description(entity)
    }
  end

  defp entity_details(entity) do
    summary = fetch_summary(get_in(entity, ["sitelinks", "enwiki", "title"]))

    # Two candidate photos per person, often different pictures: the
    # article's lead image and the Commons P18 portrait. The lead is more
    # reliable to fetch, the P18 often the better portrait, and which survives
    # a circular crop is not judgeable here. Both are offered.
    lead = get_in(summary, ["originalimage", "source"])

    Provider.Author.new(%{
      provider: id(),
      id: entity["id"],
      name: label(entity),
      description: presence(summary["extract"]) || description(entity),
      image_urls: Enum.reject([lead, p18_image_url(entity)], &is_nil/1)
    })
  end

  defp label(entity), do: get_in(entity, ["labels", "en", "value"]) || entity["id"]

  defp description(entity), do: get_in(entity, ["descriptions", "en", "value"])

  defp fetch_summary(nil), do: %{}

  defp fetch_summary(title) do
    url = @wikipedia_summary_url <> URI.encode(title, &URI.char_unreserved?/1)

    case Client.get_json(url, []) do
      {:ok, summary} when is_map(summary) -> summary
      _no_usable_summary -> %{}
    end
  end

  defp p18_image_url(entity) do
    case claim_values(entity, "P18") do
      [filename | _rest] when is_binary(filename) ->
        @commons_file_path_url <>
          URI.encode(filename, &URI.char_unreserved?/1) <> "?width=#{@image_width}"

      _no_image ->
        nil
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  defp claim_values(entity, property) do
    for claim <- get_in(entity, ["claims", property]) || [],
        value = get_in(claim, ["mainsnak", "datavalue", "value"]),
        not is_nil(value),
        do: value
  end
end
