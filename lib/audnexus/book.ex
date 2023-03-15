defmodule Audnexus.Book do
  @moduledoc """
  Audnexus Books API.
  """

  @url "https://api.audnex.us/books"

  def get(asin) do
    case Req.get("#{@url}/#{asin}", retry: false) do
      {:ok, %{status: status} = response} when status in 200..299 -> {:ok, response.body}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end
end
