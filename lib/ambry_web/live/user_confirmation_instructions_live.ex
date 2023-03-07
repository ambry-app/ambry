defmodule AmbryWeb.UserConfirmationInstructionsLive do
  use AmbryWeb, :auth_live_view

  alias Ambry.Accounts

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.auth_form_card>
      <.header>Resend confirmation instructions</.header>

      <.simple_form for={@form} id="resend_confirmation_form" phx-submit="send_instructions">
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">Resend confirmation instructions</.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center">
        <.brand_link navigate={~p"/users/register"}>Register</.brand_link>
        |
        <.brand_link navigate={~p"/users/log_in"}>Log in</.brand_link>
      </p>
    </.auth_form_card>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  @impl Phoenix.LiveView
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
