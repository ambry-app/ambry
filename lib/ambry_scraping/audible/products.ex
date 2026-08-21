defmodule AmbryScraping.Audible.Products do
  @moduledoc false

  alias AmbryScraping.Audible.Author
  alias AmbryScraping.Audible.Client
  alias AmbryScraping.Audible.Narrator
  alias AmbryScraping.Audible.Product
  alias AmbryScraping.Audible.Series
  alias AmbryScraping.HTMLToMD

  @response_groups ~w(
    category_ladders
    claim_code_url
    contributors
    media
    price
    product_attrs
    product_desc
    product_extended_attrs
    product_plan_details
    product_plans
    provided_review
    rating
    relationships
    review_attrs
    sample
    series
    sku
  )

  @doc """
  Searches the catalog.

  `query` is either a plain string (searched as keywords) or a map of
  `:title` / `:author` / `:narrator` / `:keywords`. **The distinction
  matters**: this endpoint's `title` parameter matches against the title
  alone, so passing `"Neuromancer William Gibson"` as a title finds nothing,
  while `title: "Neuromancer", author: "William Gibson"` finds it. A bare
  string therefore goes to `keywords`, which is the forgiving field.

  Options:

    * `:language` — only return products in this language (compared
      case-insensitively against Audible's language names, which are
      English words like "english", "german"). Defaults to `"english"`;
      pass `"any"` (or `nil`) to disable filtering.
    * `:marketplaces` — which regional catalogs to search, merged. Editions
      are regional: a UK-only recording is invisible to the US catalog no
      matter how it's queried.

  Answers `{:ok, products}`, `{:partial, products, unreached}` where some of
  the marketplaces answered and some did not, or `{:error, reason}` where
  none did.
  """
  def search(query, opts \\ [])

  def search("", _opts), do: {:ok, []}

  def search(query, opts) when is_binary(query), do: search(%{keywords: query}, opts)

  def search(query, opts) when is_map(query) do
    case search_params(query) do
      empty when map_size(empty) == 0 ->
        {:ok, []}

      params ->
        params
        |> search_marketplaces(Keyword.get(opts, :marketplaces, Client.default_marketplaces()))
        |> parse_all(Keyword.get(opts, :language, "english"))
    end
  end

  # Merged rather than first-hit-wins: the point of searching several
  # marketplaces is recall, and which catalog a recording lives in is exactly
  # what the operator doesn't know. Deduped by ASIN, keeping the first
  # marketplace's copy, so the configured order is a preference order.
  defp search_marketplaces(params, marketplaces) do
    Enum.reduce(marketplaces, {[], []}, fn marketplace, {products, errors} ->
      case Client.get("/catalog/products", params, marketplace: marketplace) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {products ++ List.wrap(body["products"]), errors}

        {:ok, response} ->
          {products, [{marketplace, response} | errors]}

        {:error, reason} ->
          {products, [{marketplace, reason} | errors]}
      end
    end)
  end

  # One reachable marketplace is a usable answer; all of them failing is not.
  defp parse_all({[], [{_marketplace, reason} | _rest]}, _language), do: {:error, reason}

  defp parse_all({products, errors}, language) do
    parsed =
      products
      |> Enum.uniq_by(&dedupe_key/1)
      |> Enum.map(&parse_product/1)
      |> filter_language(language)

    # **A catalog that could not be reached is not a catalog with nothing in
    # it.** This used to answer `{:ok, …}` whenever *any* marketplace came
    # back, so a rate-limited or geo-blocked region was indistinguishable
    # from a region where the book genuinely doesn't exist — which is the
    # one distinction the whole setting exists to make. The results are
    # usable and they are incomplete, and the caller is told both.
    case errors do
      [] -> {:ok, parsed}
      _some -> {:partial, parsed, unreached(errors)}
    end
  end

  # Named by region, because that is the unit the operator configured and
  # the unit they can do something about.
  defp unreached(errors) do
    errors
    |> Enum.reverse()
    |> Enum.map_join(", ", fn {marketplace, reason} -> "#{marketplace}: #{why(reason)}" end)
  end

  defp why(%{status: status}), do: "HTTP #{status}"
  defp why(%{__exception__: true} = error), do: Exception.message(error)
  defp why(reason), do: reason |> inspect() |> String.slice(0, 60)

  # NOT by ASIN: the same recording carries a *different* ASIN in each
  # regional catalog, so an ASIN key silently lets every merged marketplace
  # contribute its own copy of the same book. Title, narrators and release
  # date together identify the recording across regions; the ASIN is only a
  # last resort for a product too sparse to key on.
  defp dedupe_key(product) do
    narrators = product["narrators"] |> List.wrap() |> Enum.map_join(",", & &1["name"])

    case {product["title"], product["release_date"]} do
      {nil, _date} -> product["asin"]
      {title, date} -> {String.downcase(title), narrators, date}
    end
  end

  defp search_params(query) do
    %{
      title: query[:title],
      author: query[:author],
      narrator: query[:narrator],
      keywords: query[:keywords]
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
    |> case do
      empty when map_size(empty) == 0 ->
        empty

      params ->
        Map.merge(params, %{
          response_groups: Enum.join(@response_groups, ","),
          products_sort_by: "Relevance",
          image_sizes: "900"
        })
    end
  end

  defp filter_language(products, language) when language in [nil, "any"], do: products

  defp filter_language(products, language) do
    language = String.downcase(language)

    Enum.filter(products, &(String.downcase(&1.language || "") == language))
  end

  defp parse_product(product) do
    %Product{
      id: product["asin"],
      title: product["title"],
      authors: parse_authors(product["authors"]),
      narrators: parse_narrators(product["narrators"]),
      series: parse_series(product["series"]),
      description: parse_description(product["publisher_summary"]),
      cover_image: parse_image(product["product_images"]),
      format: product["format_type"],
      published: parse_published(product["release_date"]),
      publisher: product["publisher_name"],
      language: product["language"]
    }
  end

  defp parse_authors(nil), do: []

  defp parse_authors(authors) do
    Enum.map(authors, fn author ->
      %Author{
        id: author["asin"],
        name: author["name"]
      }
    end)
  end

  defp parse_narrators(nil), do: []

  defp parse_narrators(narrators) do
    Enum.map(narrators, fn narrator ->
      %Narrator{
        name: narrator["name"]
      }
    end)
  end

  defp parse_series(nil), do: []

  defp parse_series(series) do
    Enum.map(series, fn series ->
      %Series{
        id: series["asin"],
        sequence: series["sequence"],
        title: series["title"]
      }
    end)
  end

  defp parse_description(nil), do: nil
  defp parse_description(html), do: HTMLToMD.html_to_md(html)

  defp parse_image(%{"900" => url}) when is_binary(url), do: String.replace(url, "._SL900_", "")
  defp parse_image(_else), do: nil

  defp parse_published(nil), do: nil

  defp parse_published(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _else -> nil
    end
  end
end
