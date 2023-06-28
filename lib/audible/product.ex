defmodule Audible.Product do
  @moduledoc """
  Audible Products API.

  FIXME: deprecated
  """

  @url "https://api.audible.com/1.0/catalog/products"

  @doc """
  Returns the best matched ASIN for the given title query or `nil` if no match.
  """
  def search(title) do
    case Req.get(@url, params: [title: title, products_sort_by: "Relevance"]) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        parse_response(response.body)

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(body) do
    case Enum.map(body["products"], & &1["asin"]) do
      [] -> {:error, :not_found}
      [asin | _rest] -> {:ok, asin}
    end
  end
end
