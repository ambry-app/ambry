defmodule AmbryWeb.UserAcceptInvitationLive do
  @moduledoc false
  use AmbryWeb, :auth_live_view

  alias Ambry.Accounts

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.auth_form_card>
      <.header>
        Set Up Your Account
        <:subtitle>Choose a password to complete your account setup</:subtitle>
      </.header>

      <.simple_form for={@form} id="invitation_form" phx-submit="accept_invitation" phx-change="validate">
        <.input field={@form[:password]} type="password" placeholder="New password" required />
        <.input field={@form[:password_confirmation]} type="password" placeholder="Confirm new password" required />
        <:actions>
          <.button phx-disable-with="Setting up..." class="w-full">Set Up Account</.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-center">
        <.brand_link navigate={~p"/users/log_in"}>Back to login</.brand_link>
      </p>
    </.auth_form_card>
    """
  end

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _assigns ->
          %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  @impl Phoenix.LiveView
  def handle_event("accept_invitation", %{"user" => user_params}, socket) do
    case Accounts.accept_user_invitation(socket.assigns.user, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account set up successfully. You can now log in.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_invitation_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Invitation link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
