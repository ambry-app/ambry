defmodule Ambry.Metadata.Providers.Wikidata do
  @moduledoc """
  Person-level provider backed by Wikidata + Wikipedia + Wikimedia Commons.

  The anchor of the person level: providers keyed on *real people* rather
  than published-as author identities. Book-catalog providers can't see
  people who barely exist as catalog authors — half of a composite pen name
  (Ty Franck, of James S.A. Corey) or narrate-only people — while Wikidata
  models the humans themselves.

  Flow: Wikidata entity search, hydrated and filtered to humans (P31 = Q5)
  → bio from the Wikipedia summary-extract API (the article's lead
  section; falls back to the terse Wikidata description when a person has
  no English article) → freely-licensed photo from Commons (P18), served
  scaled through Special:FilePath.

  Zero-config and free, no API key. Registered with the author-search
  capabilities, so the person form offers it alongside the book-keyed
  author sources.
  """

  @behaviour Ambry.Metadata.Provider

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers.Wikidata.Client

  @wikidata_api "https://www.wikidata.org/w/api.php"
  @wikipedia_summary_url "https://en.wikipedia.org/api/rest_v1/page/summary/"
  @commons_file_path_url "https://commons.wikimedia.org/wiki/Special:FilePath/"

  # Commons originals can be enormous (tens of MB); Special:FilePath scales
  # server-side. 1200px is plenty for the thumbnail pipeline and on par
  # with the best book-provider image sources.
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

  # Entity search matches organizations, works, and disambiguation pages
  # too; hydrating the hits' claims lets us keep only actual humans, in
  # the search's relevance order.
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
    %Provider.Author{
      provider: id(),
      id: entity["id"],
      name: label(entity),
      description: bio(entity),
      image_url: image_url(entity)
    }
  end

  defp label(entity), do: get_in(entity, ["labels", "en", "value"]) || entity["id"]

  defp description(entity), do: get_in(entity, ["descriptions", "en", "value"])

  defp bio(entity) do
    wikipedia_extract(get_in(entity, ["sitelinks", "enwiki", "title"])) || description(entity)
  end

  defp wikipedia_extract(nil), do: nil

  defp wikipedia_extract(title) do
    url = @wikipedia_summary_url <> URI.encode(title, &URI.char_unreserved?/1)

    case Client.get_json(url, []) do
      {:ok, %{"extract" => extract}} when is_binary(extract) and extract != "" -> extract
      _no_usable_summary -> nil
    end
  end

  defp image_url(entity) do
    case claim_values(entity, "P18") do
      [filename | _rest] when is_binary(filename) ->
        @commons_file_path_url <>
          URI.encode(filename, &URI.char_unreserved?/1) <> "?width=#{@image_width}"

      _no_image ->
        nil
    end
  end

  defp claim_values(entity, property) do
    for claim <- get_in(entity, ["claims", property]) || [],
        value = get_in(claim, ["mainsnak", "datavalue", "value"]),
        not is_nil(value),
        do: value
  end
end
