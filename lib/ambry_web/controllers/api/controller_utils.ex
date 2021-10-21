defmodule AmbryWeb.API.ControllerUtils do
  @moduledoc """
  Util functions for API controllers.
  """

  def offset_from_params(params, limit) do
    page =
      case params |> Map.get("page", "1") |> Integer.parse() do
        {page, _} when page >= 1 -> page
        {_bad_page, _} -> 1
        :error -> 1
      end

    page * limit - limit
  end
end
