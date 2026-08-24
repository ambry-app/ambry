defmodule AmbryWeb.Admin.Auth do
  @moduledoc """
  Helper functions for user authentication in admin live views.
  """
  use AmbryWeb, :verified_routes

  import Phoenix.LiveView, only: [push_navigate: 2]

  alias Ambry.Accounts.User

  @doc """
  Ensures the currently mounted user is an admin user, redirects if not.

      on_mount {AmbryWeb.Admin.Auth, :ensure_mounted_admin_user}
  """
  def on_mount(:ensure_mounted_admin_user, _params, _session, socket) do
    case socket.assigns.current_user do
      nil ->
        {:halt, push_navigate(socket, to: ~p"/users/log_in")}

      %User{admin: false} ->
        {:halt, push_navigate(socket, to: ~p"/")}

      %User{admin: true} ->
        {:cont, socket}
    end
  end
end
