defmodule AmbryWeb.Admin.Layouts do
  @moduledoc false

  use AmbryWeb, :html

  alias AmbryWeb.Admin.Components

  embed_templates "layouts/*"

  attr :active_path, :string, required: true

  def side_nav(assigns) do
    ~H"""
    <nav
      id="side-bar"
      class="absolute inset-0 z-10 h-screen w-64 shrink-0 -translate-x-full transform divide-y divide-zinc-200 border-r border-zinc-200 bg-zinc-50 opacity-0 duration-100 ease-out dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900 lg:relative lg:transform-none lg:opacity-100"
      phx-click-away={Components.close_sidebar()}
      phx-window-keydown={Components.close_sidebar()}
      phx-key="escape"
    >
      <div class="flex items-center gap-3 p-4">
        <span class="cursor-pointer lg:hidden" phx-click={Components.close_sidebar()}>
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
        <.link navigate={~p"/admin/people"} class={nav_class(@active_path =~ "/admin/people")}>
          <FA.icon name="user-group" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Authors & Narrators</p>
        </.link>
        <.link navigate={~p"/admin/books"} class={nav_class(@active_path =~ "/admin/books")}>
          <FA.icon name="book" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Books</p>
        </.link>
        <.link navigate={~p"/admin/series"} class={nav_class(@active_path =~ "/admin/series")}>
          <FA.icon name="book-journal-whills" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Series</p>
        </.link>
        <.link navigate={~p"/admin/media"} class={nav_class(@active_path =~ "/admin/media")}>
          <FA.icon name="file-audio" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>Media</p>
        </.link>
        <.link navigate={~p"/admin/audit"} class={nav_class(@active_path =~ "/admin/audit")}>
          <FA.icon name="file-waveform" class="h-6 w-6 fill-current lg:h-7 lg:w-7" />
          <p>File Audit</p>
        </.link>
        <.link navigate={~p"/admin/users"} class={nav_class(@active_path =~ "/admin/users")}>
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
end
