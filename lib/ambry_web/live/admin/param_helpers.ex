defmodule AmbryWeb.Admin.ParamHelpers do
  @moduledoc """
  Helpers for handling params sent from clients.
  """

  @doc """
  Converts maps of collections sent from the client into lists of maps.

  e.g.: `%{"0" => %{...}, "1" => %{...}}` -> `[%{...}, %{...}]`
  """
  def map_to_list(params, key) do
    if Map.has_key?(params, key) do
      Map.update(params, key, [], &map_to_list/1)
    else
      Map.put(params, key, [])
    end
  end

  def map_to_list(params) when is_map(params) do
    params
    |> Enum.sort_by(fn {index, _params} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, params} -> params end)
  end

  def map_to_list(params) when is_list(params), do: params
end
