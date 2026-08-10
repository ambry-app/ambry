defmodule AmbryWeb.Admin.Layouts do
  @moduledoc false

  use AmbryWeb, :html

  alias AmbryWeb.Admin.Components

  embed_templates "layouts/*"

  attr :active_path, :string, required: true

  def side_nav(assigns) do
    ~H"""
    <%!-- Scrim behind the drawer on small screens — without it the drawer
          floats over full-brightness content and doesn't read as a layer. --%>
    <div id="side-bar-scrim" class="z-[9] bg-black/40 fixed inset-0 hidden lg:hidden" aria-hidden="true" />
    <nav
      id="side-bar"
      class="absolute inset-0 z-10 h-screen w-64 shrink-0 -translate-x-full transform bg-zinc-900 opacity-0 duration-100 ease-out lg:relative lg:transform-none lg:opacity-100"
      phx-click-away={Components.close_sidebar()}
      phx-window-keydown={Components.close_sidebar()}
      phx-key="escape"
    >
      <div class="flex items-center gap-3 p-4">
        <span class="cursor-pointer lg:hidden" phx-click={Components.close_sidebar()}>
          <.icon name="fa-bars" class="h-6 w-6 text-current lg:h-7 lg:w-7" />
        </span>
        <.link navigate={~p"/admin"} class="mt-1 flex">
          <.logo class="h-6 w-6 lg:h-7 lg:w-7" />
          <.title class="h-6 lg:h-7" />
        </.link>
      </div>
      <%!-- Grouped by how the admin is actually used: the daily intake loop,
            the catalog it feeds, and the once-a-quarter machinery — instead
            of twelve peers in one flat list. --%>
      <div class="py-3">
        <.link navigate={~p"/admin"} class={nav_class(@active_path == "/admin")}>
          <.icon name="fa-binoculars" class="h-5 w-5 text-current" />
          <p>Overview</p>
        </.link>

        <p class={group_class()}>Intake</p>
        <.link navigate={~p"/admin/inbox"} class={nav_class(@active_path =~ "/admin/inbox")}>
          <.icon name="fa-inbox" class="h-5 w-5 text-current" />
          <p>Inbox</p>
        </.link>
        <.link navigate={~p"/admin/locations"} class={nav_class(@active_path =~ "/admin/locations")}>
          <.icon name="fa-folder-tree" class="h-5 w-5 text-current" />
          <p>Locations</p>
        </.link>

        <p class={group_class()}>Library</p>
        <.link navigate={~p"/admin/books"} class={nav_class(@active_path =~ "/admin/books")}>
          <.icon name="fa-book" class="h-5 w-5 text-current" />
          <p>Books</p>
        </.link>
        <.link navigate={~p"/admin/people"} class={nav_class(@active_path =~ "/admin/people")}>
          <.icon name="fa-user-group" class="h-5 w-5 text-current" />
          <p>Authors & Narrators</p>
        </.link>
        <.link navigate={~p"/admin/series"} class={nav_class(@active_path =~ "/admin/series")}>
          <.icon name="fa-book-journal-whills" class="h-5 w-5 text-current" />
          <p>Series</p>
        </.link>
        <.link navigate={~p"/admin/groups"} class={nav_class(@active_path =~ "/admin/groups")}>
          <.icon name="fa-layer-group" class="h-5 w-5 text-current" />
          <p>Groups</p>
        </.link>
        <.link navigate={~p"/admin/universes"} class={nav_class(@active_path =~ "/admin/universes")}>
          <.icon name="fa-globe" class="h-5 w-5 text-current" />
          <p>Universes</p>
        </.link>
        <.link navigate={~p"/admin/media"} class={nav_class(@active_path =~ "/admin/media")}>
          <.icon name="fa-file-audio" class="h-5 w-5 text-current" />
          <p>Media</p>
        </.link>

        <p class={group_class()}>System</p>
        <.link navigate={~p"/admin/audit"} class={nav_class(@active_path =~ "/admin/audit")}>
          <.icon name="fa-file-waveform" class="h-5 w-5 text-current" />
          <p>File Audit</p>
        </.link>
        <.link
          navigate={~p"/admin/metadata-providers"}
          class={nav_class(@active_path =~ "/admin/metadata-providers")}
        >
          <.icon name="fa-screwdriver-wrench" class="h-5 w-5 text-current" />
          <p>Metadata Providers</p>
        </.link>
        <.link navigate={~p"/admin/settings"} class={nav_class(@active_path =~ "/admin/settings")}>
          <.icon name="fa-sliders" class="h-5 w-5 text-current" />
          <p>Settings</p>
        </.link>
        <.link navigate={~p"/admin/users"} class={nav_class(@active_path =~ "/admin/users")}>
          <.icon name="fa-users-gear" class="h-5 w-5 text-current" />
          <p>Manage Users</p>
        </.link>
      </div>
      <div class="py-3">
        <.link navigate={~p"/admin/dashboard"} class={nav_class()}>
          <.icon name="fa-brands-phoenix-framework" class="h-5 w-5 text-current" />
          <p>Phoenix Dashboard</p>
        </.link>
      </div>
      <div class="absolute bottom-0 w-full py-3">
        <.link navigate={~p"/"} class={nav_class()}>
          <.icon name="fa-arrow-right-from-bracket" class="scale-[-1] h-5 w-5 text-current" />
          <p>Exit Admin</p>
        </.link>
      </div>
    </nav>
    """
  end

  # The active item wears the brand — a bar plus a tint — instead of the same
  # gray fill hover uses; inactive rows carry a transparent bar so nothing
  # shifts when the selection moves.
  defp nav_class(active? \\ false)

  defp nav_class(true),
    do:
      "border-l-[3px] border-brand-dark bg-brand-dark/10 flex items-center gap-3 px-4 py-2 text-sm font-semibold text-zinc-100"

  defp nav_class(false),
    do:
      "hover:bg-white/5 flex items-center gap-3 border-l-[3px] border-transparent px-4 py-2 text-sm text-zinc-400 hover:text-zinc-200"

  defp group_class,
    do: "px-4 pt-4 pb-1 text-[10px] font-bold uppercase tracking-widest text-zinc-500"
end
