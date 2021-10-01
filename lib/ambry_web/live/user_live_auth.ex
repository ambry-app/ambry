defmodule AmbryWeb.UserLiveAuth do
  @moduledoc """
  Helper functions for user authentication in live views.
  """

  import Phoenix.LiveView, only: [assign_new: 3, push_redirect: 2]
  alias AmbryWeb.Router.Helpers, as: Routes

  @doc """
  Attaches current_user to `socket` assigns based on user_token or nil if it doesn't.

  ## Examples

      # In the LiveView file
      defmodule DemoWeb.PageLive do
        use Phoenix.LiveView

        on_mount {AmbryWeb.UserLiveAuth, :mount_current_user}
      end

  """
  def mount_current_user(_params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Ambry.Accounts.get_user_by_session_token(user_token)
      end)

    {:cont, socket}
  end

  def mount_current_user(_params, _session, socket) do
    {:cont, assign_new(socket, :current_user, fn -> nil end)}
  end

  @doc """
  Attaches current_user to `socket` assigns based on user_token if the token exists.
  Redirect to login page if not.

  ## Examples

      # In the LiveView file
      defmodule DemoWeb.PageLive do
        use Phoenix.LiveView

        on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}
      end

  """
  def ensure_mounted_current_user(_params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Ambry.Accounts.get_user_by_session_token(user_token)
      end)

    case socket.assigns.current_user do
      nil ->
        {:halt, push_redirect(socket, to: Routes.user_session_path(socket, :new))}

      _ ->
        {:cont, socket}
    end
  end

  def ensure_mounted_current_user(_params, _session, socket) do
    {:halt, push_redirect(socket, to: Routes.user_session_path(socket, :new))}
  end
end
