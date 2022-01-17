defmodule AmbryWeb.FirstTimeSetup.SetupLive.Index do
  @moduledoc """
  First time setup experience live-view.

  Helps create the first admin user when launching the server for the first time.
  """

  use AmbryWeb, :live_view

  alias Ambry.Accounts

  alias Surface.Components.Form

  alias Surface.Components.Form.{
    ErrorTag,
    Field,
    PasswordInput,
    Submit,
    TextInput
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    cond do
      !Application.get_env(:ambry, :first_time_setup, false) ->
        {:ok, push_redirect(socket, to: Routes.home_home_path(socket, :home))}

      Accounts.admin_exists?() ->
        {:ok, assign(socket, :state, :admin_exists)}

      :else ->
        {:ok,
         assign(socket, %{
           state: :create_user,
           changeset: Accounts.change_user_registration()
         })}
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
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("restart", _params, socket) do
    System.restart()

    {:noreply, assign(socket, :state, :restarting)}
  end
end
