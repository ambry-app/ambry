defmodule AmbryScraping.Audnexus.Authors do
  @moduledoc """
  Audnexus Authors API.

  This is much faster than the Audible scraping API and returns the same data.
  """

  @url "https://api.audnex.us/authors"

  defmodule Author do
    @moduledoc false
    defstruct [:id, :name, :description, :image]
  end

  defmodule SearchResult do
    @moduledoc false
    defstruct [:id, :name]
  end

  def details(id) do
    with {:ok, %{body: attrs}} <- Req.get("#{@url}/#{id}") do
      {:ok,
       %Author{
         id: attrs["asin"],
         name: attrs["name"],
         description: attrs["description"],
         image: image(attrs["image"])
       }}
    end
  end

  defp image(nil), do: nil
  defp image(src), do: AmbryScraping.Image.fetch_from_source(src)

  def search(name) do
    with {:ok, response} <- Req.get(@url, params: [name: name]) do
      {:ok,
       response.body
       |> Enum.map(fn attrs ->
         %SearchResult{
           id: attrs["asin"],
           name: attrs["name"]
         }
       end)
       |> Enum.uniq_by(& &1.id)}
    end
  end
end
