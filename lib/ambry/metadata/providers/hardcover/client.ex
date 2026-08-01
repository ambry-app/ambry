defmodule Ambry.Metadata.Providers.Hardcover.Client do
  @moduledoc """
  Thin GraphQL client for the Hardcover API (api.hardcover.app).

  Hardcover notes: requests need a Bearer token (free account; tokens
  expire after one year), the API is officially "still in flux" so callers
  should parse responses defensively, and the documented rate limit is
  60 requests/minute — the metadata cache keeps us well under it.
  """

  @receive_timeout 30_000

  def query(config, graphql, variables \\ %{}) do
    request =
      Req.post(
        url: endpoint(config),
        json: %{query: graphql, variables: variables},
        auth: {:bearer, token(config)},
        receive_timeout: @receive_timeout,
        retry: false
      )

    case request do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_map(data) -> {:ok, data}
      {:ok, %{status: 200, body: %{"errors" => errors}}} -> {:error, {:graphql, errors}}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 200}} -> {:error, :unexpected_response_payload}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp endpoint(config), do: config[:base_url] || "https://api.hardcover.app/v1/graphql"
  defp token(config), do: config[:api_token] || ""
end
