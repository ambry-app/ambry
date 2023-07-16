defmodule Ambry.Media.Chapters.Audnexus do
  @moduledoc """
  Imports chapter data from the Audnexus API.
  """

  require Logger

  def name do
    "Import from Audnexus"
  end

  def available?(_media), do: true

  def inputs do
    [
      %{label: "ASIN", field: :asin, type: "text"}
    ]
  end

  def get_chapters(_media, params) do
    case Audnexus.Book.chapters(params["asin"]) do
      {:ok, %{"chapters" => chapters}} when is_list(chapters) ->
        {:ok, process_chapters(chapters)}

      {:ok, response} ->
        Logger.warning(fn -> "Unexpected response received from Audnexus: #{inspect(response)}" end)
        {:error, "Unexpected response received from Audnexus"}

      {:error, %Req.Response{status: status}} ->
        {:error, status}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp process_chapters(chapters) do
    Enum.map(chapters, fn chapter ->
      %{
        title: chapter["title"],
        time: chapter["startOffsetMs"] |> Decimal.new() |> Decimal.div(1000) |> Decimal.round(2)
      }
    end)
  end
end
