defmodule AmbryWeb.Admin.UserLive.Index do
  @moduledoc """
  LiveView for user admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers

  alias Ambry.Accounts

  @valid_sort_fields [
    :email,
    :admin,
    :confirmed,
    :last_login_at
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:header_title, "Users")
     |> maybe_update_users(params, true), layout: {AmbryWeb.Admin.Layouts, :app}}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> maybe_update_users(params)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:user, nil)
    |> assign_new(:autofocus_search, fn -> false end)
  end

  defp maybe_update_users(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {users, has_more?} = list_users(list_opts)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:users, users)
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if user.id != socket.assigns.current_user.id do
      :ok = Accounts.delete_user(user)

      list_opts = get_list_opts(socket)

      params = %{
        "filter" => to_string(list_opts.filter),
        "page" => to_string(list_opts.page)
      }

      {:noreply,
       socket
       |> maybe_update_users(params, true)
       |> put_flash(:info, "User deleted successfully")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("promote", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    {:ok, _user} = Accounts.promote_user_to_admin(user)

    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    {:noreply,
     socket
     |> maybe_update_users(params, true)
     |> put_flash(:info, "User promoted to admin")}
  end

  def handle_event("demote", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if user.id != socket.assigns.current_user.id do
      {:ok, _user} = Accounts.demote_user_from_admin(user)

      list_opts = get_list_opts(socket)

      params = %{
        "filter" => to_string(list_opts.filter),
        "page" => to_string(list_opts.page)
      }

      {:noreply,
       socket
       |> maybe_update_users(params, true)
       |> put_flash(:info, "User demoted from admin")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> maybe_update_users(%{"filter" => query, "page" => "1"})
      |> assign(:autofocus_search, true)

    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/users?#{patch_opts(list_opts)}")}
  end

  defp list_users(opts) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Accounts.list_users(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort, @valid_sort_fields)
    )
  end
end
