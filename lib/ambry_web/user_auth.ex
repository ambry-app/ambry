defmodule AmbryWeb.UserAuth do
  @moduledoc """
  Helper functions for user authentication in a web context.
  """
  use AmbryWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias Ambry.Accounts
  alias Ambry.Accounts.User

  # Changing this also means changing the token expiry in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_ambry_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  Renews the session ID and clears the whole session to avoid fixation
  attacks. Sets `:live_socket_id`, so LiveView sessions are disconnected on
  log out.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # Renews the session ID and erases the whole session, to avoid fixation
  # attacks. Anything worth preserving across log in/out has to be fetched
  # before the clear and put back after it.
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      AmbryWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/users/log_in")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)

    user =
      user_token &&
        user_token |> Accounts.get_user_by_session_token() |> with_sentry_user_context()

    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Authenticates the user by looking into the Authorization header for a bearer
  token.
  """
  def fetch_api_user(conn, _opts) do
    user_token = get_token_from_header(conn)

    user =
      user_token &&
        user_token |> Accounts.get_user_by_session_token() |> with_sentry_user_context()

    conn
    |> assign(:api_user, user)
    |> assign(:api_user_token, user_token)
  end

  defp get_token_from_header(conn) do
    with ["Bearer " <> encoded_token] <- get_req_header(conn, "authorization"),
         {:ok, token} <- Base.url_decode64(encoded_token) do
      token
    else
      _anything -> nil
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

    * `:mount_current_user` — assigns `current_user`, or nil.
    * `:ensure_authenticated` — same, redirecting to login if there is none.
    * `:redirect_if_user_is_authenticated` — redirects to `signed_in_path`
      if there is one.

      live_session :authenticated, on_mount: [{AmbryWeb.UserAuth, :ensure_authenticated}]
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(session, socket)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(session, socket) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        user_token |> Accounts.get_user_by_session_token() |> with_sentry_user_context()
      end
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> unauthenticated_redirect()
    end
  end

  @doc """
  Used for routes that require the user to be an admin.
  """
  def require_admin(conn, _opts) do
    if conn.assigns.current_user.admin do
      conn
    else
      conn
      |> put_flash(:error, "You don't have access to this page.")
      |> redirect(to: signed_in_path(conn))
      |> halt()
    end
  end

  @doc """
  Used for static file routes that require the user to be authenticated.

  Works for both API requests or web requests.
  """
  def require_any_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] || conn.assigns[:api_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> text("Unauthorized")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(%{path_info: ["preview" | _rest]} = conn),
    do: conn |> current_path() |> String.replace("/preview", "")

  defp signed_in_path(_conn), do: ~p"/"

  @preview_paths ["audiobooks"]

  defp unauthenticated_redirect(%{path_info: [root | _rest]} = conn)
       when root in @preview_paths do
    conn
    |> redirect(to: "/preview#{current_path(conn)}")
    |> halt()
  end

  defp unauthenticated_redirect(conn) do
    conn
    |> redirect(to: ~p"/users/log_in")
    |> halt()
  end

  defp with_sentry_user_context(nil), do: nil

  defp with_sentry_user_context(%User{} = user) do
    Sentry.Context.set_user_context(%{
      id: user.id,
      email: user.email
    })

    user
  end
end
