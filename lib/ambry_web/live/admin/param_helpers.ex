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
      Map.update!(params, key, fn
        params_map when is_map(params_map) ->
          params_map
          |> Enum.sort_by(fn {index, _params} -> String.to_integer(index) end)
          |> Enum.map(fn {_index, params} -> params end)

        params_list when is_list(params_list) ->
          params_list
      end)
    else
      Map.put(params, key, [])
    end
  end
end
