defmodule AmbryScraping.Audible.Products do
  @moduledoc """
  Audible JSON API for products
  """

  alias AmbryScraping.HTMLToMD
  alias AmbryScraping.Image

  @url "https://api.audible.com/1.0"
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

  defmodule Product do
    @moduledoc false
    defstruct [
      :asin,
      :title,
      :authors,
      :narrators,
      :series,
      :description,
      :cover_image,
      :format,
      :published,
      :publisher,
      :language
    ]
  end

  defmodule Author do
    @moduledoc false
    defstruct [:asin, :name]
  end

  defmodule Narrator do
    @moduledoc false
    defstruct [:name]
  end

  defmodule Series do
    @moduledoc false
    defstruct [:asin, :sequence, :title]
  end

  @doc """
  Returns product details for a given title search query.
  """
  def search(query) do
    query =
      URI.encode_query(%{
        title: query,
        response_groups: Enum.join(@response_groups, ","),
        products_sort_by: "Relevance",
        image_sizes: "900"
      })

    url = "#{@url}/catalog/products" |> URI.new!() |> URI.append_query(query) |> URI.to_string()

    case Req.get(url) do
      {:ok, %{status: status} = response} when status in 200..299 -> parse_response(response.body)
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(%{"products" => products}) do
    {:ok, Enum.map(products, &parse_product/1)}
  end

  defp parse_response(_body) do
    {:error, :unexpected_response_payload}
  end

  defp parse_product(product) do
    %Product{
      asin: product["asin"],
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
        asin: author["asin"],
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

  defp parse_series(nil), do: nil

  defp parse_series(series) do
    Enum.map(series, fn series ->
      %Series{
        asin: series["asin"],
        sequence: series["sequence"],
        title: series["title"]
      }
    end)
  end

  defp parse_description(nil), do: nil

  defp parse_description(html), do: HTMLToMD.html_to_md(html)

  defp parse_image(%{"900" => url}) when is_binary(url) do
    src = String.replace(url, "._SL900_", "")

    Image.fetch_from_source(src)
  end

  defp parse_image(_else), do: nil

  defp parse_published(nil), do: nil

  defp parse_published(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _else -> nil
    end
  end
end
