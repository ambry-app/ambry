defmodule AmbryWeb.UserLoginLive do
  use AmbryWeb, :auth_live_view

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.auth_form_card>
      <.header>
        Sign in to your account
        <:subtitle>
          Welcome to Ambry! Please sign in to your account below.
          <%= if @user_registration_enabled do %>
            If you don't yet have an account, you can
            <.brand_link navigate={~p"/users/register"}>
              register for one
            </.brand_link>.
          <% end %>
        </:subtitle>
      </.header>

      <.simple_form :let={f} id="login_form" for={:user} action={~p"/users/log_in"} as={:user} phx-update="ignore">
        <.input field={{f, :email}} type="email" placeholder="Email" required />
        <.input field={{f, :password}} type="password" placeholder="Password" required />

        <:actions :let={f}>
          <.input field={{f, :remember_me}} type="checkbox" label="Remember me" />
          <.link navigate={~p"/users/reset_password"} class="text-sm font-semibold">
            Forgot your password?
          </.link>
        </:actions>
        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full">
            Sign in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </.auth_form_card>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    email = live_flash(socket.assigns.flash, :email)
    user_registration_enabled = Application.get_env(:ambry, :user_registration_enabled, false)

    {:ok, assign(socket, email: email, user_registration_enabled: user_registration_enabled),
     temporary_assigns: [email: nil]}
  end
end
