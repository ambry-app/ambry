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

      <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <.input field={@form[:password]} type="password" placeholder="Password" required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
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
    form = to_form(%{email: email}, as: "user")

    {:ok, assign(socket, form: form, user_registration_enabled: user_registration_enabled),
     temporary_assigns: [form: form]}
  end
end
