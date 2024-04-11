defmodule AmbryScraping.Audnexus.Authors do
  @moduledoc false

  alias AmbryScraping.Audnexus.Author
  alias AmbryScraping.Audnexus.AuthorDetails

  @url "https://api.audnex.us/authors"

  def details(id) do
    with {:ok, %{body: attrs}} <- Req.get("#{@url}/#{id}") do
      {:ok,
       %AuthorDetails{
         id: attrs["asin"],
         name: attrs["name"],
         description: attrs["description"],
         image: image(attrs["image"])
       }}
    end
  end

  defp image(nil), do: nil
  defp image(""), do: nil
  defp image(src), do: AmbryScraping.Image.fetch_from_source(src)

  def search(""), do: {:ok, []}

  def search(name) do
    with {:ok, response} <- Req.get(@url, params: [name: name]) do
      {:ok,
       response.body
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
