defmodule AmbryWeb.UserConfirmationInstructionsLive do
  use AmbryWeb, :live_view

  alias Ambry.Accounts

  def render(assigns) do
    ~H"""
    <div class="flex flex-col justify-center space-y-8 sm:max-w-xl sm:m-auto p-4">
      <.logo_with_tagline />

      <.auth_form_card>
        <.header>Resend confirmation instructions</.header>

        <.simple_form
          :let={f}
          for={:user}
          id="resend_confirmation_form"
          phx-submit="send_instructions"
        >
          <.input field={{f, :email}} type="email" placeholder="Email" required />
          <:actions>
            <.button phx-disable-with="Sending..." class="w-full">
              Resend confirmation instructions
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
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    info =
      "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
