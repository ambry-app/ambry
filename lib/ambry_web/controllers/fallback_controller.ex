defmodule AmbryWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use AmbryWeb, :controller

  def call(conn, _anything) do
    conn
    |> put_status(:not_found)
    |> put_view(AmbryWeb.ErrorView)
    |> render(:"404")
  end
end
