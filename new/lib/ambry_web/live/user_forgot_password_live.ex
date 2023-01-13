defmodule AmbryWeb.UserForgotPasswordLive do
  use AmbryWeb, :live_view

  alias Ambry.Accounts

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.auth_form_card>
      <.header class="text-center">
        Forgot your password?
        <:subtitle>We'll send a password reset link to your inbox</:subtitle>
      </.header>

      <.simple_form :let={f} id="reset_password_form" for={:user} phx-submit="send_email">
        <.input field={{f, :email}} type="email" placeholder="Email" required />
        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">
            Send password reset instructions
          </.button>
        </:actions>
      </.simple_form>
      <p class="text-center mt-4">
        <.brand_link navigate={~p"/users/register"}>
          Register
        </.brand_link>
        |
        <.brand_link navigate={~p"/users/log_in"}>
          Log in
        </.brand_link>
      </p>
    </.auth_form_card>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/users/log_in")}
  end
end
