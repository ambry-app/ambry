defmodule Ambry.SearchUtils do
  @moduledoc false

  def sort_by_jaro(items, query, key) do
    query = String.downcase(query)

    items
    |> Enum.map(fn item ->
      {String.jaro_distance(String.downcase(Map.fetch!(item, key)), query), item}
    end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
  end
end
