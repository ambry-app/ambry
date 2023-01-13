defmodule AmbryWeb.UserConfirmationLive do
  use AmbryWeb, :live_view

  alias Ambry.Accounts

  @impl Phoenix.LiveView
  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <.auth_form_card>
      <.header class="text-center">Confirm Account</.header>

      <.simple_form :let={f} for={:user} id="confirmation_form" phx-submit="confirm_account">
        <.input field={{f, :token}} type="hidden" value={@token} />
        <:actions>
          <.button phx-disable-with="Confirming..." class="w-full">Confirm my account</.button>
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
  def mount(params, _session, socket) do
    {:ok, assign(socket, token: params["token"]), temporary_assigns: [token: nil]}
  end

  @impl Phoenix.LiveView
  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def handle_event("confirm_account", %{"user" => %{"token" => token}}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User confirmed successfully.")
         |> redirect(to: ~p"/")}

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: ~p"/")}

          %{} ->
            {:noreply,
             socket
             |> put_flash(:error, "User confirmation link is invalid or it has expired.")
             |> redirect(to: ~p"/")}
        end
    end
  end
end
