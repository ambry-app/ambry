defmodule AmbryWeb.Admin.UserLive.Index do
  @moduledoc """
  LiveView for user admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.Gravatar

  alias Ambry.Accounts

  @valid_sort_fields [
    :email,
    :admin,
    :confirmed,
    :media_in_progress,
    :media_finished,
    :last_login_at,
    :inserted_at
  ]

  @default_sort "inserted_at.desc"

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Users",
       show_header_search: true
     )
     |> maybe_update_users(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> maybe_update_users(params)}
  end

  defp maybe_update_users(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {users, has_more?} = list_users(list_opts, @default_sort)

      assign(socket,
        list_opts: list_opts,
        users: users,
        has_next: has_more?,
        has_prev: list_opts.page > 1,
        next_page_path: ~p"/admin/users?#{next_opts(list_opts)}",
        prev_page_path: ~p"/admin/users?#{prev_opts(list_opts)}",
        current_sort: list_opts.sort || @default_sort
      )
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if user.id == socket.assigns.current_user.id do
      {:noreply, socket}
    else
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

    if user.id == socket.assigns.current_user.id do
      {:noreply, socket}
    else
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

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/users?#{patch_opts(list_opts)}")}
  end

  defp list_users(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Accounts.list_users(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
  end
end
