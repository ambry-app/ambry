defmodule Ambry.Metadata.Providers.RreadingGlasses.Client do
  @moduledoc """
  Thin HTTP client for a rreading-glasses server.

  Quirk: unknown routes on rreading-glasses return HTTP 200 with an HTML
  page (the Swagger UI), so a successful status is not enough — only a
  JSON-decoded (map or list) body counts as a valid response.
  """

  @receive_timeout 30_000

  def get_json(base_url, path, params \\ []) do
    url = String.trim_trailing(base_url, "/") <> path

    case Req.get(url: url, params: params, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: body}} when is_map(body) or is_list(body) -> {:ok, body}
      {:ok, %{status: 200}} -> {:error, :unexpected_response_payload}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end
end
