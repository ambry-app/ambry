defmodule AmbryWeb.Admin.Auth do
  @moduledoc """
  Helper functions for user authentication in admin live views.
  """

  import Phoenix.LiveView, only: [push_redirect: 2]
  alias AmbryWeb.Router.Helpers, as: Routes

  alias Ambry.Accounts.User

  @doc """
  Ensures the currently mounted user is an admin user, redirects if not.

  ## Examples

      # In the LiveView file
      defmodule DemoWeb.PageLive do
        use Phoenix.LiveView

        on_mount {AmbryWeb.Admin.Auth, :ensure_mounted_admin_user}
      end

  """
  def on_mount(:ensure_mounted_admin_user, _params, _session, socket) do
    case socket.assigns.current_user do
      nil ->
        {:halt, push_redirect(socket, to: Routes.user_session_path(socket, :new))}

      %User{admin: false} ->
        {:halt, push_redirect(socket, to: Routes.now_playing_index_path(socket, :index))}

      %User{admin: true} ->
        {:cont, socket}
    end
  end
end
