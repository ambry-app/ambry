defmodule AmbryWeb.API.SessionController do
  @moduledoc """
  Controller for logging in and out for the API.
  """

  use AmbryWeb, :controller

  alias Ambry.Accounts

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.generate_user_session_token(user)

      json(conn, %{data: %{token: Base.url_encode64(token)}})
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized"})
    end
  end

  def delete(conn, _params) do
    user_token = conn.assigns[:api_user_token]
    user_token && Accounts.delete_session_token(user_token)

    json(conn, "OK")
  end
end
