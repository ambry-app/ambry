defmodule AmbryWeb.FallbackController do
  @moduledoc """
  Returns a 404
  """
  use AmbryWeb, :controller

  def call(conn, _anything) do
    conn
    |> put_status(:not_found)
    |> put_view(AmbryWeb.ErrorHTML)
    |> render(:"404")
  end
end
