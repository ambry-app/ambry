defmodule AmbryWeb.Admin.UserLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  alias Ambry.Accounts

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Invite User", form: to_form(%{"email" => ""}, as: :user))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"user" => user_params}, socket) do
    # No validation needed for email-only form
    {:noreply, assign(socket, form: to_form(user_params, as: :user))}
  end

  def handle_event("submit", %{"user" => %{"email" => email}}, socket) do
    case Accounts.deliver_user_invitation(email, &url(~p"/users/accept_invitation/#{&1}")) do
      {:ok, _token} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent successfully")
         |> push_navigate(to: ~p"/admin/users")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to send invitation")
         |> push_navigate(to: ~p"/admin/users")}
    end
  end
end
