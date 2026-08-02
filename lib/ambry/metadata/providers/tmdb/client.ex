defmodule Ambry.Metadata.Providers.Tmdb.Client do
  @moduledoc """
  Thin HTTP client for the TMDB v3 API.

  TMDB hands out two credential shapes and both are accepted here: the
  short v3 "API key" (sent as an `api_key` query param) and the long v4
  "API Read Access Token" (a JWT, sent as a Bearer header). Operators
  paste whichever their account page gave them.
  """

  @base_url "https://api.themoviedb.org/3"
  @receive_timeout 30_000

  def get_json(path, params, config) do
    {params, headers} = authorize(params, config)

    case Req.get(
           url: @base_url <> path,
           params: params,
           headers: headers,
           receive_timeout: @receive_timeout,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize(params, config) do
    api_key = config[:api_key] || ""

    if String.starts_with?(api_key, "eyJ") do
      {params, [{"authorization", "Bearer " <> api_key}]}
    else
      {Keyword.put(params, :api_key, api_key), []}
    end
  end
end
