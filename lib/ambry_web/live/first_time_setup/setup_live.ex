defmodule AmbryWeb.FirstTimeSetup.SetupLive do
  @moduledoc """
  First time setup experience live-view.

  Helps create the first admin user when launching the server for the first time.
  """

  use AmbryWeb, :live_view

  alias Ambry.Accounts

  @impl Phoenix.LiveView
  def render(%{state: :create_user} = assigns) do
    ~H"""
    <.auth_form_card>
      <.header>
        First Time Setup
        <:subtitle>
          Welcome to <span class="text-brand font-semibold dark:text-brand-dark">Ambry</span>!
          To get started, let's create the admin user account that will be managing this server.
        </:subtitle>
      </.header>

      <.simple_form for={@form} phx-submit="save">
        <.note>
          The email is only ever used to email password reset emails if needed, and
          only if emailing has been set up.
        </.note>

        <.input field={@form[:email]} type="email" placeholder="Email" required />

        <.note>
          Your password needs to be at least 12 characters long, and contain at least
          one each of lower case, upper case, and special characters.
        </.note>

        <.input field={@form[:password]} type="password" placeholder="Password" required />

        <:actions>
          <.button phx-disable-with="Please wait..." class="w-full">
            Register <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </.auth_form_card>
    """
  end

  def render(%{state: state} = assigns) when state in [:admin_exists, :restarting] do
    ~H"""
    <.auth_form_card>
      <.header>
        First Time Setup
        <:subtitle>
          You're all set! We now need to restart the server for the changes to take effect.
          You can try clicking the button below, but depending on how you're running the server,
          you may need to restart it manually.
        </:subtitle>
      </.header>

      <.restart_button state={@state} />
    </.auth_form_card>
    """
  end

  defp restart_button(%{state: :admin_exists} = assigns) do
    ~H"""
    <.button class="w-full" phx-click="restart">
      Restart <FA.icon name="rotate" class="ml-2 inline h-4 w-4" aria-hidden="true" />
    </.button>
    """
  end

  defp restart_button(%{state: :restarting} = assigns) do
    ~H"""
    <.button class="w-full" disabled>
      Restarting... <FA.icon name="rotate" class="ml-2 inline h-4 w-4 animate-spin" aria-hidden="true" />
    </.button>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    cond do
      !Application.get_env(:ambry, :first_time_setup, false) ->
        {:ok, push_navigate(socket, to: ~p"/")}

      Accounts.admin_exists?() ->
        {:ok, assign(socket, :state, :admin_exists)}

      :else ->
        {:ok,
         socket
         |> assign(state: :create_user)
         |> assign_form(Accounts.change_user_registration())}
    end
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Welcome")
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"user" => user_params}, socket) do
    with {:ok, user} <- Accounts.register_user(user_params),
         {:ok, _user} <- Accounts.promote_user_to_admin(user) do
      Ambry.FirstTimeSetup.disable!()

      {:noreply,
       socket
       |> put_flash(:info, "User created successfully")
       |> assign(:state, :admin_exists)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("restart", _params, socket) do
    System.restart()

    {:noreply, assign(socket, :state, :restarting)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
