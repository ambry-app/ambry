defmodule AmbryWeb.Admin.Auth do
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
  def ensure_mounted_admin_user(_params, _session, socket) do
    case socket.assigns.current_user do
      nil ->
        {:halt, push_redirect(socket, to: Routes.user_session_path(socket, :new))}

      %User{admin: false} ->
        {:halt, push_redirect(socket, to: Routes.home_home_path(socket, :home))}

      %User{admin: true} ->
        {:cont, socket}
    end
  end
end
