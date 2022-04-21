defmodule AmbryWeb.Admin.Components do
  @moduledoc """
  Shared function components used throughout the admin area.
  """

  use AmbryWeb, :component

  alias AmbryWeb.Endpoint
  alias AmbryWeb.Router.Helpers, as: Routes

  def side_nav(assigns) do
    ~H"""
    <nav
      class="
        absolute inset-0
        transform lg:transform-none
        lg:opacity-100 duration-100
        lg:relative
        z-10 w-64
        bg-gray-50 dark:bg-gray-900
        border-r border-gray-200 dark:border-gray-800
        divide-y divide-gray-200 dark:divide-gray-800
        h-screen
      "
      :class="{'translate-x-0 ease-in opacity-100':open === true, '-translate-x-full ease-out opacity-0': open === false}"
    >
      <div class="p-4 flex gap-3 items-center">
        <span class="cursor-pointer lg:hidden" @click="open = false">
          <FA.icon name="bars" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
        </span>
        <.link link_type="live_redirect" to={Routes.admin_home_index_path(Endpoint, :index)} class="flex">
          <Amc.ambry_icon class="w-6 h-6 lg:w-7 lg:h-7" />
          <Amc.ambry_title class="h-6 lg:h-7" />
        </.link>
      </div>
      <div class="py-3">
        <.link
          link_type="live_redirect"
          to={Routes.admin_home_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin")}
        >
          <FA.icon name="binoculars" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Overview</p>
        </.link>
        <.link
          link_type="live_redirect"
          to={Routes.admin_person_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/people")}
        >
          <FA.icon name="user-group" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Authors & Narrators</p>
        </.link>
        <.link
          link_type="live_redirect"
          to={Routes.admin_book_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/books")}
        >
          <FA.icon name="book" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Books</p>
        </.link>
        <.link
          link_type="live_redirect"
          to={Routes.admin_series_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/series")}
        >
          <FA.icon name="book-journal-whills" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Series</p>
        </.link>
        <.link
          link_type="live_redirect"
          to={Routes.admin_media_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/media")}
        >
          <FA.icon name="file-audio" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Media</p>
        </.link>
        <.link
          link_type="live_redirect"
          to={Routes.admin_audit_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/audit")}
        >
          <FA.icon name="file-waveform" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>File Audit</p>
        </.link>
        <.link
          link_type="live_redirect"
          to={Routes.admin_user_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/users")}
        >
          <FA.icon name="users-gear" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Manage Users</p>
        </.link>
      </div>
      <div class="py-3">
        <.link link_type="live_redirect" to={Routes.live_dashboard_path(Endpoint, :home)} class={nav_class()}>
          <FA.icon name="phoenix-framework" type="brands" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Phoenix Dashboard</p>
        </.link>
      </div>
      <div class="py-3 absolute bottom-0 w-full">
        <.link link_type="live_redirect" to="/" class={nav_class()}>
          <FA.icon name="arrow-right-from-bracket" class="w-6 h-6 lg:w-7 lg:h-7 fill-current scale-[-1]" />
          <p>Exit Admin</p>
        </.link>
      </div>
    </nav>
    """
  end

  defp nav_class(active? \\ false)
  defp nav_class(true), do: "flex items-center px-4 py-2 gap-4 bg-gray-300 dark:bg-gray-700"

  defp nav_class(false),
    do: "flex items-center px-4 py-2 gap-4 hover:bg-gray-300 dark:hover:bg-gray-700"

  def header(assigns) do
    ~H"""
    <header
      x-data
      class="p-4 flex gap-3 items-center border-gray-100 dark:border-gray-900"
      :class="{ 'border-b': $store.header.scrolled }"
    >
      <span class="cursor-pointer lg:hidden" @click="open = true">
        <FA.icon name="bars" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
      </span>
      <.link link_type="live_redirect" to={Routes.admin_home_index_path(Endpoint, :index)} class="flex lg:hidden">
        <Amc.ambry_icon class="w-6 h-6 lg:w-7 lg:h-7" />
        <Amc.ambry_title class="h-6 lg:h-7 hidden sm:block" />
      </.link>
      <div class="flex-grow text-2xl font-bold pl-0 sm:pl-4 lg:pl-0"><%= @title %></div>
      <div x-data="{ open: false }" @click.outside="open = false" @keydown.escape.window.prevent="open = false">
        <img @click="open = !open" class="h-6 lg:w-7 lg:h-7 rounded-full cursor-pointer" src={gravatar_url(@user.email)} />
        <Amc.admin_menu user={@user} />
      </div>
    </header>
    """
  end

  def admin_table_header(assigns) do
    ~H"""
    <div class="flex items-center">
      <.admin_table_search_form filter={@list_opts.filter} autofocus_search={@autofocus_search} />
      <div class="flex-grow" />
      <%= if @new_path do %>
        <div class="px-2">
          <.link
            link_type="live_patch"
            to={@new_path}
            class="flex items-center font-bold text-lime-500 dark:text-lime-400 hover:underline"
          >
            New <FA.icon name="plus" class="w-4 h-4 fill-current ml-2" />
          </.link>
        </div>
      <% end %>
      <div class="px-2">
        <.pagination_chevron active={@list_opts.page > 1} name="chevron-left" to={@prev_page} />
      </div>
      <div class="px-2">
        <.pagination_chevron active={@has_more} name="chevron-right" to={@next_page} />
      </div>
    </div>
    """
  end

  defp admin_table_search_form(assigns) do
    ~H"""
    <.form let={f} for={:search} phx-submit="search">
      <%= search_input(f, :query,
        id: "searchInput",
        placeholder: "Search",
        value: @filter,
        class: "
            w-full bg-transparent
            border-0 focus:outline-none focus:ring-0 focus:border-0
            placeholder:font-bold placeholder:text-gray-500
            border-b border-gray-200 dark:border-gray-800
            focus:border-b focus:border-lime-500 dark:focus:border-lime-400
            mb-2 px-0
          ",
        "phx-autofocus": @autofocus_search
      ) %>
    </.form>
    """
  end

  defp pagination_chevron(assigns) do
    ~H"""
    <%= if @active do %>
      <.link link_type="live_patch" to={@to} class="cursor-pointer">
        <FA.icon
          name={@name}
          class="
            w-5 h-5 fill-current
            text-gray-600 dark:text-gray-500
            hover:text-gray-900 dark:hover:text-gray-100
          "
        />
      </.link>
    <% else %>
      <FA.icon name={@name} class="w-5 h-5 fill-current dark:text-gray-900" />
    <% end %>
    """
  end

  def admin_table(assigns) do
    assigns = assign_new(assigns, :row_click, fn -> true end)

    default_cell_class =
      if assigns.row_click, do: "p-3 text-left cursor-pointer", else: "p-3 text-left"

    default_header_class = "p-3 text-left"

    row_class =
      if assigns.row_click,
        do:
          "border-t border-gray-200 hover:bg-gray-200 dark:border-gray-800 dark:hover:bg-gray-700",
        else: "border-t border-gray-200 dark:border-gray-800"

    ~H"""
    <div class="bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-md tran">
      <%= if @rows == [] do %>
        <div class="p-3">
          <%= render_slot(@no_results) %>
        </div>
      <% else %>
        <table class="w-full">
          <thead>
            <tr>
              <%= for col <- @col do %>
                <th class={[col[:class], default_header_class]}><%= col.label %></th>
              <% end %>

              <%= if assigns[:actions] do %>
                <th class={[assigns[:actions_class], default_header_class]} />
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @rows do %>
              <tr class={row_class}>
                <%= for col <- @col do %>
                  <%= if @row_click do %>
                    <td class={[col[:class], default_cell_class]} phx-click="row-click" phx-value-id={row.id}>
                      <%= render_slot(col, row) %>
                    </td>
                  <% else %>
                    <td class={[col[:class], default_cell_class]}>
                      <%= render_slot(col, row) %>
                    </td>
                  <% end %>
                <% end %>

                <%= if assigns[:actions] do %>
                  <td class={[assigns[:actions_class], default_cell_class]}>
                    <%= render_slot(@actions, row) %>
                  </td>
                <% end %>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  @badge_colors %{
    "yellow" => "
      border-yellow-200 bg-yellow-50
      dark:border-yellow-400 dark:bg-yellow-400
    ",
    "blue" => "
      border-blue-200 bg-blue-50
      dark:border-blue-400 dark:bg-blue-400
    ",
    "red" => "
      border-red-200 bg-red-50
      dark:border-red-400 dark:bg-red-400
    ",
    "lime" => "
      border-lime-200 bg-lime-50
      dark:border-lime-400 dark:bg-lime-400
    ",
    "gray" => "
      border-gray-200 bg-gray-100
      dark:border-gray-400 dark:bg-gray-400
    "
  }

  defp badge_color_classes(color), do: @badge_colors[color]

  def admin_badge(assigns) do
    ~H"""
    <span class={"px-1 border rounded-md text-gray-900 whitespace-nowrap" <> badge_color_classes(@color)}>
      <%= @label %>
    </span>
    """
  end
end
