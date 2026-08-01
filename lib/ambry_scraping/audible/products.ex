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
  Returns product details for a given title search query.

  Options:

    * `:language` — only return products in this language (compared
      case-insensitively against Audible's language names, which are
      English words like "english", "german"). Defaults to `"english"`;
      pass `"any"` (or `nil`) to disable filtering.
  """
  def search(query, opts \\ [])

  def search("", _opts), do: {:ok, []}

  def search(query, opts) do
    params = %{
      title: query,
      response_groups: Enum.join(@response_groups, ","),
      products_sort_by: "Relevance",
      image_sizes: "900"
    }

    case Client.get("/catalog/products", params) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        parse_response(response.body, Keyword.get(opts, :language, "english"))

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(%{"products" => products}, language) do
    {:ok, products |> Enum.map(&parse_product/1) |> filter_language(language)}
  end

  defp parse_response(_body, _language) do
    {:error, :unexpected_response_payload}
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
