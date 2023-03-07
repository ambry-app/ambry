defmodule AmbryWeb.Admin.Layouts do
  @moduledoc false

  use AmbryWeb, :html

  import AmbryWeb.Gravatar

  embed_templates "layouts/*"

  def side_nav(assigns) do
    ~H"""
    <nav
      id="side-bar"
      class="absolute inset-0 z-10 h-screen w-64 flex-shrink-0 -translate-x-full transform divide-y divide-zinc-200 border-r border-zinc-200 bg-zinc-50 opacity-0 duration-100 ease-out dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900 lg:relative lg:transform-none lg:opacity-100"
      phx-click-away={close_sidebar()}
      phx-window-keydown={close_sidebar()}
      phx-key="escape"
    >
      <div class="flex items-center gap-3 p-4">
        <span class="cursor-pointer lg:hidden" phx-click={close_sidebar()}>
          <FA.icon name="bars" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
        </span>
        <.link navigate={~p"/admin"} class="mt-1 flex">
          <.logo class="h-6 w-6 lg:h-7 lg:w-7" />
          <.title class="h-6 lg:h-7" />
        </.link>
      </div>
      <div class="py-3">
        <.link navigate={~p"/admin"} class={nav_class(@active_path == "/admin")}>
          <FA.icon name="binoculars" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Overview</p>
        </.link>
        <.link navigate={~p"/admin/people"} class={nav_class(@active_path == "/admin/people")}>
          <FA.icon name="user-group" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Authors & Narrators</p>
        </.link>
        <.link navigate={~p"/admin/books"} class={nav_class(@active_path == "/admin/books")}>
          <FA.icon name="book" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Books</p>
        </.link>
        <.link navigate={~p"/admin/series"} class={nav_class(@active_path == "/admin/series")}>
          <FA.icon name="book-journal-whills" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Series</p>
        </.link>
        <.link navigate={~p"/admin/media"} class={nav_class(@active_path == "/admin/media")}>
          <FA.icon name="file-audio" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Media</p>
        </.link>
        <.link navigate={~p"/admin/audit"} class={nav_class(@active_path == "/admin/audit")}>
          <FA.icon name="file-waveform" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>File Audit</p>
        </.link>
        <.link navigate={~p"/admin/users"} class={nav_class(@active_path == "/admin/users")}>
          <FA.icon name="users-gear" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Manage Users</p>
        </.link>
      </div>
      <div class="py-3">
        <.link navigate={~p"/admin/dashboard"} class={nav_class()}>
          <FA.icon name="phoenix-framework" type="brands" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Phoenix Dashboard</p>
        </.link>
      </div>
      <div class="absolute bottom-0 w-full py-3">
        <.link navigate={~p"/"} class={nav_class()}>
          <FA.icon name="arrow-right-from-bracket" class="scale-[-1] h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Exit Admin</p>
        </.link>
      </div>
    </nav>
    """
  end

  defp nav_class(active? \\ false)
  defp nav_class(true), do: "flex items-center px-4 py-2 gap-4 bg-zinc-300 dark:bg-zinc-700"

  defp nav_class(false),
    do: "flex items-center px-4 py-2 gap-4 hover:bg-zinc-300 dark:hover:bg-zinc-700"

  def dashboard_header(assigns) do
    ~H"""
    <header
      x-data
      class="flex items-center gap-3 border-zinc-100 p-4 dark:border-zinc-900"
      x-class="{ 'border-b': $store.header.scrolled }"
    >
      <span class="cursor-pointer lg:hidden" phx-click={open_sidebar()}>
        <FA.icon name="bars" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
      </span>
      <.link navigate={~p"/admin"} class="flex lg:hidden">
        <.logo class="h-6 w-6 lg:h-7 lg:w-7" />
        <.title class="hidden h-6 sm:block lg:h-7" />
      </.link>
      <div class="flex-grow pl-0 text-2xl font-bold sm:pl-4 lg:pl-0"><%= @title %></div>
      <div phx-click-away={hide_menu("admin-user-menu")} phx-window-keydown={hide_menu("admin-user-menu")} phx-key="escape">
        <img
          phx-click={toggle_menu("admin-user-menu")}
          class="mt-1 h-6 cursor-pointer rounded-full lg:h-7 lg:w-7"
          src={gravatar_url(@user.email)}
        />
        <.admin_menu user={@user} />
      </div>
    </header>
    """
  end

  def admin_menu(assigns) do
    ~H"""
    <.menu_wrapper id="admin-user-menu" user={@user}>
      <div class="py-3">
        <.link navigate={~p"/"} class="flex items-center gap-4 px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700">
          <FA.icon name="arrow-right-from-bracket" class="scale-[-1] h-5 w-5 fill-current" />
          <p>Exit Admin</p>
        </.link>
        <.link
          href={~p"/users/log_out"}
          method="delete"
          class="flex items-center gap-4 px-4 py-2 hover:bg-gray-300 dark:hover:bg-gray-700"
        >
          <FA.icon name="arrow-right-from-bracket" class="h-5 w-5 fill-current" />
          <p>Log out</p>
        </.link>
      </div>
    </.menu_wrapper>
    """
  end

  @side_bar_open_classes "translate-x-0 ease-in opacity-100"
  @side_bar_closed_classes "-translate-x-full ease-out opacity-0"

  defp close_sidebar do
    %JS{}
    |> JS.remove_class(@side_bar_open_classes, to: "#side-bar")
    |> JS.add_class(@side_bar_closed_classes, to: "#side-bar")
  end

  defp open_sidebar do
    %JS{}
    |> JS.remove_class(@side_bar_closed_classes, to: "#side-bar")
    |> JS.add_class(@side_bar_open_classes, to: "#side-bar")
  end
end
