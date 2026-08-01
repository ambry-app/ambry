defmodule Ambry.Metadata.Providers.RreadingGlasses.Client do
  @moduledoc """
  Thin HTTP client for a rreading-glasses server.

  Two quirks require care here:

    * Valid JSON responses can arrive with `content-type: text/plain` (seen
      on the public instance behind Cloudflare), so Req's automatic JSON
      decoding cannot be relied on — binary bodies are decoded explicitly.
    * Unknown routes return HTTP 200 with an HTML page (the Swagger UI), so
      a successful status is not enough — only a body that decodes as JSON
      counts as a valid response.
  """

  @receive_timeout 30_000

  def get_json(base_url, path, params \\ []) do
    url = String.trim_trailing(base_url, "/") <> path

    case Req.get(url: url, params: params, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: body}} -> decode(body)
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(body) when is_map(body) or is_list(body), do: {:ok, body}

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :unexpected_response_payload}
    end
  end

  defp decode(_body), do: {:error, :unexpected_response_payload}
end
