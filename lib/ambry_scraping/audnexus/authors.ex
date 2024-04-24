defmodule AmbryScraping.Audnexus.Authors do
  @moduledoc false

  alias AmbryScraping.Audnexus.Author
  alias AmbryScraping.Audnexus.AuthorDetails
  alias AmbryScraping.Audnexus.Client

  def details(id) do
    case Client.get("/authors/#{id}") do
      {:ok, %{status: status, body: attrs}} when status in 200..299 ->
        {:ok,
         %AuthorDetails{
           id: attrs["asin"],
           name: attrs["name"],
           description: attrs["description"],
           image: image(attrs["image"])
         }}

      {:ok, %{status: status}} when status in 400..499 ->
        {:error, :not_found}

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp image(nil), do: nil
  defp image(""), do: nil
  defp image(src), do: src

  def search(""), do: {:ok, []}

  def search(name) do
    with {:ok, %{status: 200, body: body}} <- Client.get("/authors", params: [name: name]) do
      {:ok,
       body
       |> Enum.map(fn attrs ->
         %Author{
           id: attrs["asin"],
           name: attrs["name"]
         }
       end)
       |> Enum.uniq_by(& &1.id)}
    end
  end
end
