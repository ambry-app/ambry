defmodule AmbryWeb.Admin.Components do
  @moduledoc """
  Shared function components used throughout the admin area.
  """

  use AmbryWeb, :p_component

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
        z-10 w-80
        bg-gray-50 dark:bg-gray-900
        border-r border-gray-200 dark:border-gray-800
        divide-y divide-gray-200 dark:divide-gray-800
        h-screen
      "
      :class="{'translate-x-0 ease-in opacity-100':open === true, '-translate-x-full ease-out opacity-0': open === false}"
    >
      <div class="p-4 flex gap-3 items-center">
        <span
          class="cursor-pointer lg:hidden"
          @click="open = false"
        >
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
          to={Routes.admin_person_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/people")}
        >
          <FA.icon name="users" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Authors & Narrators</p>
        </.link>
        <.link
          link_type="live_redirect"
          to={Routes.admin_book_index_path(Endpoint, :index)}
          class={nav_class(@active_path == "/admin/books")}
        >
          <FA.icon name="book-open" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
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
      </div>
      <div class="py-3">
        <.link
          link_type="live_redirect"
          to={Routes.live_dashboard_path(Endpoint, :home)}
          class={nav_class()}
        >
          <FA.icon name="phoenix-framework" type="brands" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
          <p>Phoenix Dashboard</p>
        </.link>
      </div>
      <div class="py-3 absolute bottom-0 w-full">
        <.link
          link_type="live_redirect"
          to="/"
          class={nav_class()}
        >
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
    <header class="p-4 flex gap-3 items-center">
      <span
        class="cursor-pointer lg:hidden"
        @click="open = true"
      >
        <FA.icon name="bars" class="w-6 h-6 lg:w-7 lg:h-7 fill-current" />
      </span>
      <.link link_type="live_redirect" to={Routes.admin_home_index_path(Endpoint, :index)} class="flex lg:hidden">
        <Amc.ambry_icon class="w-6 h-6 lg:w-7 lg:h-7" />
        <Amc.ambry_title class="h-6 lg:h-7" />
      </.link>
      <div class="flex-grow" />
      <div
        x-data="{ open: false }"
        @click.outside="open = false"
        @keydown.escape.window.prevent="open = false"
      >
        <img
          @click="open = !open"
          class="h-6 lg:w-7 lg:h-7 rounded-full cursor-pointer"
          src={gravatar_url(@user.email)}
        />
        <Amc.admin_menu user={@user} />
      </div>
    </header>
    """
  end
end
