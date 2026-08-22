defmodule AmbryWeb.Admin.Layouts do
  @moduledoc false

  use AmbryWeb, :html

  alias AmbryWeb.Admin.Components

  embed_templates "layouts/*"

  attr :active_path, :string, required: true
  attr :inbox_pending, :integer, default: 0

  def side_nav(assigns) do
    ~H"""
    <%!-- Scrim behind the drawer on small screens — without it the drawer
          floats over full-brightness content and doesn't read as a layer. --%>
    <div id="side-bar-scrim" class="bg-black/40 z-[60] fixed inset-0 hidden lg:hidden" aria-hidden="true" />
    <%!-- `fixed`, not a flex child of an `h-screen` shell: the nav is the one
          thing on the page that genuinely doesn't scroll, and saying so here
          is what lets the document scroll everywhere else. `inset-y-0` is a
          real viewport height now that `h-screen` is no longer a JS-measured
          custom property. --%>
    <nav
      id="side-bar"
      class="z-[70] fixed inset-y-0 left-0 flex w-64 -translate-x-full transform flex-col bg-zinc-900 opacity-0 duration-100 ease-out lg:transform-none lg:opacity-100"
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
      <%!-- The links scroll, the logo and the way out don't. The nav is
            ~720px of items, so on a short laptop window it used to be
            silently clipped by the shell's `overflow-hidden` — and the way
            out was an `absolute bottom-0` block sitting on top of whatever
            it overlapped. --%>
      <div class="grow overflow-y-auto">
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
            <%!-- The one count in the nav, because the inbox is the one item
                that is a queue. Amber only while there is something in it;
                a zero would just be a badge that never goes away. --%>
            <span
              :if={@inbox_pending > 0}
              class="bg-amber-400/15 ml-auto rounded-full px-1.5 text-xs font-bold tabular-nums text-amber-300"
              data-role="inbox-pending-badge"
            >
              {@inbox_pending}
            </span>
          </.link>
          <%!-- No count here. The inbox badge is the only one in the nav
                because the inbox is the only item that is a queue; what is
                coming is a date, not a backlog, and it nags from the
                dashboard where it can say which book. --%>
          <.link navigate={~p"/admin/watches"} class={nav_class(@active_path =~ "/admin/watches")}>
            <.icon name="fa-eye" class="h-5 w-5 text-current" />
            <p>Watching</p>
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
          <.link navigate={~p"/admin/sets"} class={nav_class(@active_path =~ "/admin/sets")}>
            <.icon name="fa-layer-group" class="h-5 w-5 text-current" />
            <p>Sets</p>
          </.link>
          <.link navigate={~p"/admin/universes"} class={nav_class(@active_path =~ "/admin/universes")}>
            <.icon name="fa-globe" class="h-5 w-5 text-current" />
            <p>Universes</p>
          </.link>
          <.link navigate={~p"/admin/audiobooks"} class={nav_class(@active_path =~ "/admin/audiobooks")}>
            <.icon name="fa-file-audio" class="h-5 w-5 text-current" />
            <p>Audiobooks</p>
          </.link>

          <p class={group_class()}>System</p>
          <.link navigate={~p"/admin/duplicates"} class={nav_class(@active_path =~ "/admin/duplicates")}>
            <.icon name="fa-magnifying-glass" class="h-5 w-5 text-current" />
            <p>Duplicates</p>
          </.link>
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
          <%!-- Phoenix's own dashboard, like Oban's, is a different application
                wearing the same auth. Sending the operator there in the same tab
                costs them whatever they were on; the icon is what says so before
                they click. --%>
          <.link href={~p"/admin/dashboard"} target="_blank" rel="noopener" class={nav_class()}>
            <.icon name="fa-brands-phoenix-framework" class="h-5 w-5 text-current" />
            <p>Phoenix Dashboard</p>
            <.icon name="fa-arrow-up-right-from-square" class="ml-auto h-3 w-3 text-current" />
          </.link>
        </div>
      </div>
      <div class="flex-none py-3">
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
