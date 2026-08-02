defmodule Ambry.Metadata.Providers.Wikidata.Client do
  @moduledoc """
  Thin HTTP client for the Wikimedia APIs (the Wikidata action API and the
  Wikipedia REST summary endpoint).

  Wikimedia's API etiquette requires a descriptive User-Agent identifying
  the application and a contact point — generic library UAs risk being
  throttled or blocked.
  """

  @receive_timeout 30_000

  def get_json(url, params) do
    case Req.get(
           url: url,
           params: params,
           headers: [{"user-agent", user_agent()}],
           receive_timeout: @receive_timeout,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} -> decode(body)
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(body) when is_map(body), do: {:ok, body}

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :unexpected_response_payload}
    end
  end

  defp decode(_body), do: {:error, :unexpected_response_payload}

  defp user_agent do
    "Ambry/#{Application.spec(:ambry, :vsn)} (https://github.com/ambry-app/ambry)"
  end
end
