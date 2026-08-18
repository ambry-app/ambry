defmodule AmbryWeb.Admin.Components do
  @moduledoc false

  use AmbryWeb, :html

  import Ambry.Utils, only: [name_credit: 1, series_credit: 1]
  import AmbryWeb.Gravatar
  import AmbryWeb.TimeUtils, only: [duration_display: 1]

  alias Ambry.Accounts.User
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField

  attr :user, User, required: true
  attr :title, :string, required: true
  # The header hosts a nested LiveView, which needs the parent socket to
  # mount into. Required rather than defaulted: a default would answer "a
  # new admin page forgot it" by silently dropping the indicator from that
  # one page, which is the failure mode this project keeps paying for.
  # Required makes it a compile warning, and CI treats warnings as errors.
  attr :socket, Phoenix.LiveView.Socket, required: true

  slot :inner_block, required: true
  slot :subheader

  def layout(assigns) do
    ~H"""
    <div class="min-w-0">
      <.layout_header user={@user} title={@title} socket={@socket}>
        {render_slot(@subheader)}
      </.layout_header>

      <%!-- `#main-content` keeps its id and its `p-4` — the sticky-footer hook
            and §3's sticky-bar arithmetic both name it — but it is no longer a
            scrollport. It was `overflow-y-auto` inside an `h-screen` shell,
            and that one declaration is why nothing in the admin could remember
            a scroll position: LiveView's restoration reads and writes
            `window.scrollY` and nothing else.

            `overflow-x-clip` is what's left of the `overflow-x-hidden` it used
            to carry. `hidden` on one axis forces the other to `auto`, which
            would quietly make this a scrollport again and re-break every
            sticky box inside it; `clip` guards a stray wide child without
            becoming a scroll container. --%>
      <main id="main-content" class="overflow-x-clip p-4">
        {render_slot(@inner_block)}
      </main>

      <%!-- The image lightbox — tiny previews and chips are for telling
          records apart, and sometimes that takes the full-size art. Opened
          by any [data-zoomable] magnifier (see app.js); click or Escape
          closes. phx-update="ignore": it's pure client state.

          Top of the ladder on layout_header/1: it opens from inside content
          that a modal may itself be covering. --%>
      <div
        id="image-lightbox"
        phx-update="ignore"
        class="bg-black/85 z-[70] fixed inset-0 hidden cursor-zoom-out items-center justify-center p-8 backdrop-blur"
      >
        <img class="max-h-full max-w-full rounded-sm object-contain shadow-2xl" />
      </div>
    </div>
    """
  end

  attr :user, User, required: true
  attr :title, :string, required: true
  attr :socket, Phoenix.LiveView.Socket, required: true

  slot :inner_block, required: true

  # The z-index ladder, now that content scrolls *under* the chrome instead of
  # inside a box below it. Everything here shares the root stacking context —
  # an `index_row` is `relative` with no z-index, so its `z-10` rail and `z-20`
  # busy overlay are not scoped to the card, and a row that scrolled under a
  # z-10 header would have painted straight over it (same index, later in the
  # DOM, later wins).
  #
  #   10/20  row internals (rail, busy overlay)
  #   30     this header
  #   40     the drawer's scrim
  #   50     the side nav drawer
  #   60     a modal — it covers the viewport, and the nav is part of what it
  #          is covering, so it sits above the nav rather than beside it
  #   70     the image lightbox, which opens from inside a modal's content
  defp layout_header(assigns) do
    ~H"""
    <header
      id="nav-header"
      phx-hook="header-scrollspy"
      class="sticky top-0 z-30 space-y-4 border-zinc-900 bg-zinc-950 p-4"
    >
      <div class="flex items-center gap-3">
        <span class="cursor-pointer lg:hidden" phx-click={open_sidebar()}>
          <.icon name="fa-bars" class="h-6 w-6 text-current lg:h-7 lg:w-7" />
        </span>
        <.link navigate={~p"/admin"} class="flex lg:hidden">
          <.logo class="h-6 w-6 lg:h-7 lg:w-7" />
          <.title class="hidden h-6 sm:block lg:h-7" />
        </.link>
        <div class="grow overflow-hidden text-ellipsis whitespace-nowrap pl-0 text-2xl font-bold text-zinc-100 sm:pl-4 lg:pl-0">
          {@title}
        </div>
        <%!-- A LiveView of its own, not a component: it polls, and a poll
              that lives on the page's socket makes the page re-render every
              tick. Sticky so a live navigation doesn't tear it down and
              rebuild it, which would blink the spinner off mid-job. --%>
        {live_render(@socket, AmbryWeb.Admin.JobIndicatorLive,
          id: "admin-job-indicator",
          sticky: true
        )}
        <div
          phx-click-away={hide_menu("admin-user-menu")}
          phx-window-keydown={hide_menu("admin-user-menu")}
          phx-key="escape"
          class="flex-none"
        >
          <img
            phx-click={toggle_menu("admin-user-menu")}
            class="mt-1 h-6 cursor-pointer rounded-full lg:h-7 lg:w-7"
            src={gravatar_url(@user.email)}
          />
          <.admin_menu user={@user} />
        </div>
      </div>
      {render_slot(@inner_block)}
    </header>
    """
  end

  attr :search_form, Form, default: nil
  attr :new_path, :string, default: nil
  attr :new_text, :string, default: "New"

  slot :inner_block

  @doc """
  The header's controls: how you narrow a list, and how you add to it.

  Paging used to live here too, as two bare chevrons in the top right corner.
  That put the control for moving through a list as far from the list as the
  page allows, gave no page number and no total, and — because the header
  doesn't move — meant a "next page" click left the scroll where it was, so
  the operator arrived looking at the *bottom* of the page they just asked
  for. It is `pagination_footer/1` now, under the last row.
  """
  def list_controls(assigns) do
    ~H"""
    <div class="flex items-end gap-4">
      <div class="grow">
        <.admin_table_search_form search_form={@search_form} />
      </div>
      <%!-- A list page's one constructive action, so it wears §6's primary
            costume — the same solid button the inbox's "Scan for new" has
            always had in this exact slot. It was a lime text link everywhere
            else, which read as navigation rather than the page's point. --%>
      <div :if={@new_path}>
        <.button navigate={@new_path}>
          <.icon name="fa-plus" class="mr-2 h-4 w-4 text-current" />{@new_text}
        </.button>
      </div>
    </div>
    """
  end

  defp admin_menu(assigns) do
    ~H"""
    <.menu_wrapper id="admin-user-menu" user={@user}>
      <div class="py-3">
        <.link navigate={~p"/"} class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-700">
          <.icon name="fa-arrow-right-from-bracket" class="scale-[-1] h-5 w-5 text-current" />
          <p>Exit Admin</p>
        </.link>
        <.link
          href={~p"/users/log_out"}
          method="delete"
          class="flex items-center gap-4 px-4 py-2 hover:bg-zinc-700"
        >
          <.icon name="fa-arrow-right-from-bracket" class="h-5 w-5 text-current" />
          <p>Log out</p>
        </.link>
      </div>
    </.menu_wrapper>
    """
  end

  @side_bar_open_classes "translate-x-0 ease-in opacity-100"
  @side_bar_closed_classes "-translate-x-full ease-out opacity-0"

  def close_sidebar do
    %JS{}
    |> JS.remove_class(@side_bar_open_classes, to: "#side-bar")
    |> JS.add_class(@side_bar_closed_classes, to: "#side-bar")
    |> JS.hide(
      to: "#side-bar-scrim",
      transition: {"transition-opacity ease-out duration-100", "opacity-100", "opacity-0"}
    )
  end

  defp open_sidebar do
    %JS{}
    |> JS.remove_class(@side_bar_closed_classes, to: "#side-bar")
    |> JS.add_class(@side_bar_open_classes, to: "#side-bar")
    |> JS.show(
      to: "#side-bar-scrim",
      transition: {"transition-opacity ease-in duration-100", "opacity-0", "opacity-100"}
    )
  end

  attr :search_form, Form, required: true

  defp admin_table_search_form(assigns) do
    ~H"""
    <.form for={@search_form} phx-submit="search" data-role="search-form">
      <%!-- A real field, not a bare underline — the search is an interactive
            control and should look like one before it's focused. --%>
      <div class="relative max-w-md">
        <.icon
          name="fa-magnifying-glass"
          class="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-zinc-500"
        />
        <%!-- The app-standard fill, like every other control. It used to wear
              a 1px border and its own two-step lime focus ring — the one
              control on a list page, looking unlike every control on the page
              it leads to. --%>
        <input
          id={@search_form.id}
          type="search"
          name={@search_form[:query].name}
          value={@search_form[:query].value}
          placeholder="Search"
          class={input_classes("w-full py-1.5 pr-3 pl-9")}
        />
      </div>
    </.form>
    """
  end

  attr :info, :map, required: true, doc: "from `PaginationHelpers.page_info/3`"
  attr :has_next, :boolean, required: true
  attr :has_prev, :boolean, required: true
  attr :next_page_path, :string, required: true
  attr :prev_page_path, :string, required: true

  @doc """
  Where a list says how far through it you are, and moves you.

  Under the last row, in the scroll flow, because that is where the operator
  is when they want it — and because a control that never moves cannot say
  "you have reached the end of this page", which is the whole cue for using
  it. It carries the numbers the chevrons never had: which rows these are,
  how many there are, and which page of how many.

  A `zinc-900` bar, so it reads as a peer of `sort_button_bar/1` at the other
  end of the list rather than as another row.
  """
  def pagination_footer(assigns) do
    ~H"""
    <div
      :if={@has_prev or @has_next}
      class="mt-3 flex flex-wrap items-center justify-between gap-x-4 gap-y-2 rounded-lg bg-zinc-900 px-4 py-3"
      data-role="pagination"
    >
      <%!-- "1 to 50", not "1&ndash;50": §8 keeps en dashes out of rendered
            text and joins with words instead. --%>
      <p class="text-sm text-zinc-400" data-role="pagination-range">
        <%= if @info.first do %>
          Showing {@info.first} to {@info.last}{if @info.total, do: " of #{@info.total}"}
        <% else %>
          Nothing on this page
        <% end %>
      </p>

      <div class="flex items-center gap-2">
        <.pagination_step active={@has_prev} to={@prev_page_path} icon="fa-chevron-left">
          Previous
        </.pagination_step>

        <%!-- Tabular figures, so the number doesn't jitter the buttons
              sideways as the operator pages through. --%>
        <p class="px-1 text-sm tabular-nums text-zinc-400" data-role="pagination-page">
          Page {@info.page}{if @info.pages, do: " of #{@info.pages}"}
        </p>

        <.pagination_step active={@has_next} to={@next_page_path} icon="fa-chevron-right" trailing>
          Next
        </.pagination_step>
      </div>
    </div>
    """
  end

  attr :active, :boolean, required: true
  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :trailing, :boolean, default: false, doc: "put the glyph after the word"
  slot :inner_block, required: true

  # Worded, like every other action in this admin (§3a): two bare chevrons in
  # a corner were the only control on a list page that made you know what a
  # glyph meant. An unavailable step is present and dead rather than absent,
  # so the bar keeps its shape at both ends of the list.
  defp pagination_step(assigns) do
    ~H"""
    <%= if @active do %>
      <.link
        patch={@to}
        class="flex items-center gap-2 rounded-lg bg-zinc-800 px-3 py-1.5 text-sm font-semibold text-zinc-100 hover:bg-zinc-700"
      >
        <.icon :if={!@trailing} name={@icon} class="h-3 w-3 text-current" />
        {render_slot(@inner_block)}
        <.icon :if={@trailing} name={@icon} class="h-3 w-3 text-current" />
      </.link>
    <% else %>
      <span class="flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm font-semibold text-zinc-600">
        <.icon :if={!@trailing} name={@icon} class="h-3 w-3 text-current" />
        {render_slot(@inner_block)}
        <.icon :if={@trailing} name={@icon} class="h-3 w-3 text-current" />
      </span>
    <% end %>
    """
  end

  @doc """
  The shell a list page's rows sit in: the spacing, and what an empty list
  says.

  The rows themselves are `index_row/1`. This used to own their geometry too,
  through a `:row` slot and a `row_click` callback, which meant every surface
  hand-built its own anatomy inside one anonymous slot — and ten of them
  drifted apart doing it.
  """
  attr :id, :string, default: "list", doc: "the list-scroll-reset hook needs one"
  attr :rows, :list, required: true
  attr :filter, :string, default: nil

  attr :list_state, :any,
    default: nil,
    doc: "what identifies this view (page, filter, sort). A change scrolls back to the top."

  slot :empty
  slot :row, required: true

  def flex_table(assigns) do
    ~H"""
    <%!-- The hook lives out here rather than on the rows, so it survives a
          filter that empties the list and is still mounted when the next one
          fills it again. --%>
    <div id={@id} phx-hook="list-scroll-reset" data-list-state={inspect(@list_state)}>
      <%= if @rows == [] do %>
        <p :if={@empty} class="text-lg font-semibold" data-role="empty-message">
          <%= if @filter do %>
            No results for "{@filter}"
          <% else %>
            {render_slot(@empty)}
          <% end %>
        </p>
      <% else %>
        <%!-- Rows are separate raised cards on the ground, not one bordered slab
              sliced by hairline dividers — elevation and gaps do the separating. --%>
        <div class="space-y-3">
          <div :for={row <- @rows}>{render_slot(@row, row)}</div>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  One row of a list page, in the one anatomy they all share.

  **The whole card is the link.** The headline is a real `<a>` whose `::after`
  covers the card, which is the only way to get both halves of what the two
  older idioms each had half of: the library lists made the whole row
  clickable with `JS.navigate` on the div (a big target, but not a link — no
  focus, no middle click, no open-in-new-tab), and the inbox linked only its
  title (a real link, a 200px target). It also fixes a defect neither idiom
  could see: LiveView dispatches a click to the *closest* `phx-click`
  ancestor, so an `<a>` nested inside a `JS.navigate` row fired the anchor
  **and** the row, which on the users list meant clicking Devices also
  navigated to Playthroughs.

  Everything the operator can click therefore sits in a `z-10` layer above
  that pseudo-element; the busy overlay is `z-20` and covers both.

  The slots are the anatomy, and each has exactly one home:

    * `:cover` — a 64px image, at the card's left edge (§3: an image is
      content, so it sits on the rail like the words beside it).
    * `:headline` — the title. Always the link, always `font-semibold`.
    * `:inner_block` — the credit stack and meta lines under the headline.
    * `:badges` — state, at the top of the right rail, on the headline's
      baseline. Not under the cover: one home per kind of thing, and the
      media list was the only surface that put them there.
    * `:facts` — the glyph-and-count strip. It used to be its own
      `hidden sm:flex` column, which didn't fold on a phone, it *vanished*.
    * `:action` — one entry per verb, worded. Never icon-only: §6's exception
      for that was written for a five-verb media row whose verbs have all
      since moved onto the form.
    * `:footer` — **system timestamps only** (added, imported, joined, last
      seen). A publication date and a duration are facts about the work, not
      a record of something the app did, and reading them in the column that
      says "Added 8/17/26" made them look like both.

  **The rail is 224px, which is two buttons wide, and actions wrap.** Four
  buttons stacked one per line is tall and ragged; two rows of two is neither.
  So the rail is sized to the pair rather than the label, and the constraint
  that falls out is on the *labels*: keep them short enough that two fit
  ("Origin", not "Import record"). One slot entry per verb is what keeps them
  all in one costume.
  """
  attr :navigate, :string, default: nil, doc: "where the whole card goes; omit for a dead row"
  attr :patch, :string, default: nil, doc: "same, when the destination is a patch (a modal)"

  attr :class, :any,
    default: nil,
    doc: "per-item state, e.g. the queue's `border-l-4` rail"

  attr :inert, :boolean,
    default: false,
    doc: "takes the row's content out of the tab order, for a row an :overlay owns"

  attr :rest, :global

  slot :overlay, doc: "a scrim over the whole card, e.g. `busy_overlay/1`"
  slot :cover
  slot :headline
  slot :badges
  slot :facts
  slot :footer
  slot :inner_block

  slot :action do
    attr :navigate, :string
    attr :patch, :string
    attr :icon, :string, required: true
    attr :color, :atom, doc: "one of zinc (default), brand, or red"
    attr :click, :string, doc: "a phx-click event name"
    attr :value, :any, doc: "the phx-value-id that rides with it"
    attr :confirm, :string
    attr :title, :string
    attr :disabled, :boolean
    attr :role, :string, doc: "a data-role, for tests"
  end

  def index_row(assigns) do
    ~H"""
    <%!-- flex-wrap below sm lets the right rail drop to a full-width bottom
          line instead of squeezing the content column on phones. --%>
    <div
      class={[
        "relative flex flex-wrap items-center gap-x-4 gap-y-2 rounded-lg bg-zinc-900 p-4 sm:flex-nowrap",
        (@navigate || @patch) && "hover:bg-zinc-800/50",
        @class
      ]}
      {@rest}
    >
      <%!-- A direct child of the card, so its `inset-0` measures the card and
            nothing clips it: the content column below is `overflow-hidden`,
            which would have cropped a scrim rendered inside it. --%>
      {render_slot(@overlay)}

      <div :if={@cover != []} class="flex-none" inert={@inert}>{render_slot(@cover)}</div>

      <div class="min-w-0 flex-grow overflow-hidden" inert={@inert}>
        <p :if={@headline != []} class="overflow-hidden text-ellipsis whitespace-nowrap font-semibold">
          <%= if @navigate || @patch do %>
            <%!-- after:inset-0 against the card's own `relative`: the anchor
                  stays an ordinary inline element (so the headline still
                  truncates and wraps normally) and only its pseudo-element
                  spreads to the card's edges. --%>
            <.link navigate={@navigate} patch={@patch} class="after:absolute after:inset-0">
              {render_slot(@headline)}
            </.link>
          <% else %>
            {render_slot(@headline)}
          <% end %>
        </p>

        {render_slot(@inner_block)}
      </div>

      <%!-- The rail's corners share the card's baselines: the badges align
            with the headline, the dates with the content's last line
            (self-stretch + justify-between — without the stretch the column
            is content-height and justify-between does nothing, which is why
            the older lists' dates sat jammed under their icons). --%>
      <div
        :if={[@badges, @facts, @action, @footer] != [[], [], [], []]}
        class="relative z-10 flex w-full flex-none flex-wrap items-center gap-x-3 gap-y-2 sm:w-56 sm:flex-col sm:items-end sm:justify-between sm:self-stretch"
        inert={@inert}
      >
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5 sm:flex-col sm:items-end">
          <div :if={@badges != []} class="flex flex-wrap items-center gap-1.5">
            {render_slot(@badges)}
          </div>

          <%!-- The row's measurements: counts, boolean glyphs, a duration, a
                publication date. Wraps rather than overflowing, because this
                is the one strip whose contents vary most per surface. --%>
          <div
            :if={@facts != []}
            class="flex flex-wrap items-center justify-end gap-x-3 gap-y-1 text-xs text-zinc-400"
          >
            {render_slot(@facts)}
          </div>

          <%!-- Content-sized and right-aligned, not one fixed width per rail:
                that rule was written when the queue stacked four identical
                buttons, and sharing one rail across every list would force
                the widest label anywhere onto every "Edit". Right alignment
                is what makes the edge read as a column; the fixed width never
                was. Which of the two layouts applies is decided by the number
                of verbs, never by what fits. --%>
          <div
            :if={@action != []}
            class="flex flex-wrap items-center justify-end gap-1.5"
            data-role="row-actions"
          >
            <.row_action
              :for={action <- @action}
              navigate={action[:navigate]}
              patch={action[:patch]}
              icon={action.icon}
              color={Map.get(action, :color, :zinc)}
              disabled={Map.get(action, :disabled, false)}
              phx-click={action[:click]}
              phx-value-id={action[:value]}
              data-confirm={action[:confirm]}
              data-role={action[:role]}
              title={action[:title]}
            >
              {render_slot(action)}
            </.row_action>
          </div>
        </div>

        <div
          :if={@footer != []}
          class="whitespace-nowrap text-right text-xs text-zinc-400"
          data-role="row-footer"
        >
          {render_slot(@footer)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The credit stack's own lines: bare author names, then the narrators muted.

  What is left of the stack once the series moves to `record_meta/1` — and
  what is left is exactly the part every record has, which is what lets a row
  be three fixed lines and one variable one. Names join with commas and
  nothing is prefixed with "by" (§8); "Read by" is the one word that stays,
  because a list of names with no label is a list of authors.
  """
  attr :authors, :list, default: []
  attr :narrators, :list, default: []

  def credit_lines(assigns) do
    ~H"""
    <p
      :if={@authors != []}
      class="overflow-hidden text-ellipsis whitespace-nowrap text-sm text-zinc-300"
    >
      {names(@authors)}
    </p>
    <%!-- A dozen-strong GraphicAudio cast printed in full buries the title
          it was meant to help identify, so the row credits the narrator who
          tells two recordings apart and counts the rest (§8). --%>
    <p
      :if={@narrators != []}
      class="overflow-hidden text-ellipsis whitespace-nowrap text-sm text-zinc-400"
    >
      Read by {name_credit(@narrators)}
    </p>
    """
  end

  defp names(people), do: Enum.map_join(people, ", ", & &1.name)

  @doc """
  A row's last line: where it sits, when it came out, who put it out, how
  long it is.

  **The row's first lines are what every record has, and this line is
  everything that varies.** Title, authors and narrators are always there, so
  they are always three lines; series, publisher, published and duration are
  each sometimes there, so they share the fourth and it collapses to nothing
  when a record has none of them. A series that owned a line of its own made
  every audiobook row taller for a fact most rows state in four words.

  It lives with the credits rather than in the rail because it is prose and
  reads like it — "The Stormlight Archive #1 · Published August 30, 2022 by
  Recorded Books · 32 hours and 43 minutes". These spent a while as terse
  cells in the rail (`8/30/22`, `14:04:02`), which is the shape a spreadsheet
  wants, not a reader.

  Takes either flat view: a book has no publisher and no duration, so it
  reduces to its series and its date.
  """
  def record_meta(record) do
    [
      record |> Map.get(:series) |> series_credit(),
      published_clause(record),
      record |> Map.get(:duration) |> duration_display()
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp published_clause(record) do
    case {format_published(record), Map.get(record, :publisher)} do
      {nil, _publisher} -> nil
      {published, nil} -> "Published #{published}"
      {published, publisher} -> "Published #{published} by #{publisher}"
    end
  end

  @doc """
  One worded action on a list row, in the one costume they all wear.

  A link when it goes somewhere, a `role="button"` span when it fires an
  event — the two the older lists spelled out by hand, differently, on every
  surface. `:red` reveals the danger fill on hover rather than wearing it, so
  a row of actions doesn't read as a row of warnings (§6).
  """
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :icon, :string, required: true
  attr :color, :atom, default: :zinc, doc: "one of zinc, brand, or red"

  attr :disabled, :boolean,
    default: false,
    doc: "present but refusing, so the rail keeps its shape and its order"

  attr :rest, :global, include: ~w(title)

  slot :inner_block, required: true

  # A disabled action is still an action: it holds its place and its order.
  #
  # `disabled:` variants are a `:disabled` pseudo-class, which a `<span>` can
  # never match, so the refusing state is spelled out. It also drops the click
  # binding rather than relying on `pointer-events-none` alone — that stops a
  # mouse and nothing else.
  def row_action(%{disabled: true} = assigns) do
    ~H"""
    <span
      role="button"
      aria-disabled="true"
      class={[row_action_class(@color), "pointer-events-none opacity-40"]}
      {Map.drop(@rest, [:"phx-click", :"phx-value-id", :"data-confirm"])}
    >
      <.icon name={@icon} class="h-3 w-3 text-current" />{render_slot(@inner_block)}
    </span>
    """
  end

  def row_action(%{navigate: nil, patch: nil} = assigns) do
    ~H"""
    <span role="button" class={row_action_class(@color)} {@rest}>
      <.icon name={@icon} class="h-3 w-3 text-current" />{render_slot(@inner_block)}
    </span>
    """
  end

  def row_action(assigns) do
    ~H"""
    <.link navigate={@navigate} patch={@patch} class={row_action_class(@color)} {@rest}>
      <.icon name={@icon} class="h-3 w-3 text-current" />{render_slot(@inner_block)}
    </.link>
    """
  end

  defp row_action_class(:red),
    do: [action_classes(:zinc), "hover:bg-red-400/10 hover:text-red-300"]

  defp row_action_class(color), do: action_classes(color)

  @doc """
  A count with its glyph, for the row rail's facts strip.

  Numbers first, glyph after — the number is what is being read and the
  glyph says which number it is.
  """
  attr :icon, :string, required: true
  attr :count, :integer, default: nil
  attr :rest, :global, include: ~w(title)

  def row_fact(assigns) do
    ~H"""
    <span class="flex items-center gap-1 tabular-nums" {@rest}>
      {@count}<.icon name={@icon} class="h-3.5 w-3.5 text-current" />
    </span>
    """
  end

  attr :busy, :boolean, required: true
  attr :label, :string, required: true
  attr :rest, :global

  @doc """
  Covers whatever it sits in while a background job owns it.

  The inbox does everything in background jobs, and a form whose draft is
  about to be rebuilt under the operator looked exactly like one waiting for
  them to type in it. Matching now keeps retrying until every provider has
  answered, so that window is minutes rather than moments, and anything typed
  into it would be silently discarded by work nobody could see.

  So it is deliberately a **scrim over the whole thing**, not a badge in a
  corner: the point is that the row or the form is not yours right now, and
  that reads at a glance from across the page in a way a status chip does not.

  Must be placed inside a `relative` container. The scrim swallows clicks by
  covering them; `inert` on the content beside it is what actually stops
  keyboard focus, and the LiveView refuses the events anyway — the overlay is
  the explanation, not the enforcement.
  """
  def busy_overlay(assigns) do
    ~H"""
    <div
      :if={@busy}
      class="bg-zinc-950/70 backdrop-blur-[1px] absolute inset-0 z-20 flex items-center justify-center gap-2 rounded-lg"
      data-role="busy-overlay"
      aria-live="polite"
      {@rest}
    >
      <.icon name="fa-rotate" class="h-4 w-4 animate-spin text-zinc-300" />
      <span class="text-sm font-semibold text-zinc-200">{@label}</span>
    </div>
    """
  end

  slot :inner_block, required: true

  def sort_button_bar(assigns) do
    ~H"""
    <div class="flex flex-wrap justify-between rounded-lg bg-zinc-900 font-bold">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :sort_field, :string, required: true
  attr :current_sort, :string, required: true
  slot :inner_block, required: true

  def sort_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="sort"
      phx-value-field={@sort_field}
      data-role="sort-button"
      class="flex cursor-pointer select-none items-center gap-2 p-2"
    >
      {render_slot(@inner_block)}
      <.sort_icon sort={@current_sort} sort_field={@sort_field} />
    </button>
    """
  end

  attr :sort, :string, required: true
  attr :sort_field, :string, required: true

  defp sort_icon(assigns) do
    {field, dir} = sort_field_and_dir(assigns.sort)

    assigns =
      assign(assigns,
        active: assigns.sort_field == field,
        dir: dir
      )

    ~H"""
    <.icon
      name={sort_icon_name(@active, @dir)}
      class={["h-4 w-4 ", if(@active, do: "text-current", else: "text-zinc-600")]}
    />
    """
  end

  defp sort_field_and_dir(nil), do: {nil, nil}

  defp sort_field_and_dir(sort) do
    case String.split(sort, ".") do
      [""] -> {nil, nil}
      [key] -> {key, "asc"}
      [key, dir] -> {key, dir}
      _else -> {nil, nil}
    end
  end

  defp sort_icon_name(false, _dir), do: "fa-sort"
  defp sort_icon_name(true, "asc"), do: "fa-sort-up"
  defp sort_icon_name(true, "desc"), do: "fa-sort-down"
  defp sort_icon_name(_active, _dir), do: "fa-sort"

  @doc """
  Renders a colored badge with a label in it.

  ## Examples

      <.badge color={:red}>Foo</.badge>
  """
  attr :color, :atom, doc: "one of yellow, blue, red, brand, or gray"
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(title)
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <%!-- A soft tint with colored text, not a solid bright pill: status is
          information, and a page of solid chips shouts. Borderless — the
          admin separates by fill, not hairlines. --%>
    <div
      class={["inline-block whitespace-nowrap rounded-sm px-1.5", badge_color(@color), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A microlabel — the quiet uppercase word that names a row of things
  (`Proposed`, `Asked`, an eyebrow). One spec everywhere, per the admin
  design language (docs/admin-design-language.md §2).
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def microlabel(assigns) do
    ~H"""
    <span class={["text-[11px] font-medium uppercase tracking-wider text-zinc-400", @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  A fold, drawn to the geometry rules: the summary text on the text rail,
  the chevron hanging in the 12px gutter to its left
  (docs/admin-design-language.md §3).

  Browsers place the native summary marker where they like — Firefox renders
  it `inside`, which pushes the summary text off the rail by the marker's own
  width — so the native marker is hidden and the chevron drawn by hand.
  """
  attr :summary, :string, default: nil
  attr :class, :string, default: nil, doc: "summary text classes — replaces the size and color"
  attr :container_class, :string, default: nil

  attr :open, :boolean,
    default: nil,
    doc: "pins the fold open from the server — a client-toggled open dies on the next patch"

  attr :rest, :global
  slot :inner_block, required: true

  slot :summary_slot,
    doc: "richer summary content (counts, muted asides) — used instead of `summary` when given"

  def disclosure(assigns) do
    ~H"""
    <details class={["group", @container_class]} open={@open} {@rest}>
      <summary class={[
        "relative cursor-pointer list-none pl-3 :[&:-webkit-details-marker]:hidden",
        @class || "text-xs text-zinc-400"
      ]}>
        <%!-- Two icons swapped on open, not one rotated: rotating the CSS-mask
            span rasterizes a grey sliver of the box edge past the mask. --%>
        <.icon
          name="fa-chevron-right"
          class="absolute top-1/2 left-0 h-2.5 w-2.5 -translate-y-1/2 group-open:hidden"
        />
        <.icon
          name="fa-chevron-down"
          class="absolute top-1/2 left-0 hidden h-2.5 w-2.5 -translate-y-1/2 group-open:inline-block"
        />
        {(@summary_slot != [] && render_slot(@summary_slot)) || @summary}
      </summary>
      {render_slot(@inner_block)}
    </details>
    """
  end

  defp badge_color(:yellow), do: "bg-amber-400/15 text-amber-300"
  defp badge_color(:blue), do: "bg-blue-400/15 text-blue-300"
  defp badge_color(:red), do: "bg-red-400/15 text-red-300"
  defp badge_color(:brand), do: "bg-brand-dark/15 text-lime-300"
  defp badge_color(:gray), do: "bg-white/10 text-zinc-300"

  attr :field, FormField, required: true

  def image_delete_button(assigns) do
    ~H"""
    <label class="flex">
      <input type="checkbox" name={@field.name} value="" class="hidden" />
      <.icon name="fa-trash" class="h-4 w-4 cursor-pointer text-current transition-colors hover:text-red-600" />
    </label>
    """
  end

  attr :field, FormField, required: true

  def delete_input(assigns) do
    ~H"""
    <input type="hidden" name={@field.name <> "[]"} />
    """
  end

  attr :field, FormField, required: true
  attr :index, :integer, required: true

  def sort_input(assigns) do
    ~H"""
    <input type="hidden" name={@field.name <> "[]"} value={@index} />
    """
  end

  attr :field, FormField, required: true
  attr :index, :integer, required: true
  attr :class, :string, default: nil, doc: "class overrides"

  def delete_button(assigns) do
    ~H"""
    <%!-- ✕, not a trash can: removing a row from a list is the import form's
        remove idiom (undoable until save), and two removal costumes for one
        gesture read as two different gestures. --%>
    <button
      type="button"
      name={@field.name <> "[]"}
      value={@index}
      phx-click={JS.dispatch("change")}
      class={["flex", @class]}
    >
      <.icon name="fa-xmark" class="h-4 w-4 cursor-pointer text-current transition-colors hover:text-red-400" />
    </button>
    """
  end

  @doc """
  Carries a row's place in the list back to the server.

  Not decoration: a reorder that changes no field is invisible to Ecto —
  `cast_assoc` returns `:ignore` when every child changeset comes back empty,
  and the new order is silently dropped. This input is what makes a moved row
  a real change. See `AmbryWeb.Admin.Reordering`.
  """
  attr :field, FormField, required: true
  attr :index, :integer, required: true

  def position_input(assigns) do
    ~H"""
    <input type="hidden" name={@field.name} value={@index} />
    """
  end

  @doc """
  Up/down buttons for reordering one entry of an ordered association.

  The button at each end of the list is rendered disabled rather than hidden,
  so the controls don't shift horizontally as rows move past them.
  """
  attr :field, :atom, required: true, doc: "the association field being reordered"
  attr :index, :integer, required: true
  attr :count, :integer, required: true
  attr :class, :string, default: nil

  def move_buttons(assigns) do
    ~H"""
    <%!-- The control is exactly one input tall (`py-[7px]` + `leading-6` +
        the transparent border = 40px) with its glyphs centred in it, so it
        lines up with the field it reorders by being the same height as it —
        design language §7. Every call site used to nudge it down by a
        hand-picked `mt-3` instead, which lands 2px shy and slides off
        entirely as soon as the row carries an error or a second control. --%>
    <div class={["flex h-10 flex-none flex-col justify-center", @class]} data-role="move-buttons">
      <button
        type="button"
        phx-click="move"
        phx-value-field={@field}
        phx-value-index={@index}
        phx-value-direction="up"
        disabled={@index == 0}
        title="Move up"
        data-role="move-up"
        class="disabled:opacity-25"
      >
        <.icon
          name="fa-chevron-up"
          class="h-3 w-3 text-current transition-colors hover:text-lime-400"
        />
      </button>
      <button
        type="button"
        phx-click="move"
        phx-value-field={@field}
        phx-value-index={@index}
        phx-value-direction="down"
        disabled={@index == @count - 1}
        title="Move down"
        data-role="move-down"
        class="disabled:opacity-25"
      >
        <.icon
          name="fa-chevron-down"
          class="h-3 w-3 text-current transition-colors hover:text-lime-400"
        />
      </button>
    </div>
    """
  end

  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true
  slot :add, doc: "the add-a-row control, rendered under the block like the import form's"

  @doc """
  One cluster of fields on an edit form, as a block.

  The edit forms were a single stack of bare controls on the ground while the
  import form was entirely blocks — the same operator, the same records, two
  visual languages. A cluster is the unit: the fields that answer one
  question about the record ("who wrote it", "where it lives"), on the
  zinc-900 block every other decision in this admin sits on.

  The label is the cluster's name and sits on the text rail, so it lines up
  with the text inside the controls under it (§3). Fields that speak for
  themselves need no label — the block and its spacing are the grouping.
  """
  def field_group(assigns) do
    ~H"""
    <%!-- **A block holds the whole cluster: its name, its rows, and the way
        to add one.** The import form is the other shape — each row there is
        its own decision card, so its label and its add have nowhere to be
        but the ground above and below the run. Here there is one block, so
        everything about the cluster lives in it. Same costumes either way;
        what differs is whether the list has a card of its own. --%>
    <div class={["space-y-2 rounded-lg bg-zinc-900 p-4", @class]} {@rest}>
      <.label :if={@label} class="pl-3">{@label}</.label>
      <p :if={@hint} class="max-w-prose pl-3 text-sm text-zinc-400">{@hint}</p>
      {render_slot(@inner_block)}
      {render_slot(@add)}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :hint, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true
  slot :add, doc: "the add_button, below the container on the ground"
  slot :proposals, doc: "a curation proposal row, inside the container after the rows"
  slot :flag, doc: "a provenance flag beside the label — where a list's members came from"

  @doc """
  A list the operator is building — authors, series, narrators — in the one
  grammar every form shares: **the card names itself** (label, provenance
  flag and hint at the top of the container, on the rail), rows follow, the
  add sits below the container on the ground.

  The label lived *above* the container for a while, which put the same
  fact's name in a different place than every decision card, field group and
  library-root block — all of which carry their name inside. One rule now:
  ground level is for section headings and helper prose only; everything a
  card says about itself, it says inside.
  """
  def list_cluster(assigns) do
    ~H"""
    <div class={["space-y-2", @class]} {@rest}>
      <div class="space-y-2 rounded-lg bg-zinc-900 p-4">
        <div class="flex items-baseline gap-2 pl-3">
          <.label>{@label}</.label>
          {render_slot(@flag)}
        </div>
        <p :if={@hint} class="max-w-prose pl-3 text-sm text-zinc-400">{@hint}</p>
        {render_slot(@inner_block)}
        {render_slot(@proposals)}
      </div>
      {render_slot(@add)}
    </div>
    """
  end

  attr :id, :string, default: "form-footer", doc: "the sticky-footer hook needs one"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @doc """
  The sticky footer slab every form's actions sit in.

  One costume for "where a form is saved": the shadowed `zinc-900` slab the
  import form has always had, instead of a bare button floating on the
  ground after the last card. The chapters form is the argument — 47 rows
  long, with the Save at the bottom of the scroll.

  §3's sticky-bar rule applies, and the document being the scroller is what
  sets the offset: a sticky box is positioned against its scrollport, and the
  viewport has no padding, so `bottom-0` puts the slab flush with the bottom
  of the window. (It was `-bottom-4` when `#main-content` was the scrollport,
  reaching through that box's own `p-4`.) The page's content wrapper still
  wears `-mb-4`, for the other half: a sticky box can't leave its containing
  block, so without it the wrapper's bottom edge holds the bar 16px up at the
  end of the scroll.
  """
  def form_footer(assigns) do
    ~H"""
    <%!-- The sticky-footer hook rounds the bottom corners (and drops the
        floating shadow) whenever the page has nothing to scroll — a slab
        that never sticks is an ordinary card and dresses like one. --%>
    <section
      id={@id}
      phx-hook="sticky-footer"
      class={["shadow-[0_-12px_32px_rgba(0,0,0,0.55)] sticky bottom-0 rounded-t-lg bg-zinc-900 p-4", @class]}
      {@rest}
    >
      <div class="flex flex-wrap items-center gap-2">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :files, :list, required: true
  attr :label, :string, default: nil, doc: "the card names itself — rendered inside, on the rail"
  attr :class, :any, default: nil

  @doc """
  A read-only list of files: mono, muted, the common directory printed once.

  This is a fact display, not a control — it deliberately does NOT wear the
  dashed dropzone costume the media form used to put its file list in, which
  made "the files you have" look like a place to drop more.

  Long lists scroll *inside* the card — the label and common-directory line
  stay pinned, and the scrollbar sits in its own gutter (`pr-2`), the same
  anatomy as the chapter editor's rows.
  """
  def file_list(assigns) do
    assigns = assign(assigns, :common, common_dir(assigns.files))

    ~H"""
    <div :if={@files != []} class={["space-y-1 rounded-lg bg-zinc-900 p-4", @class]}>
      <.label :if={@label} class="pl-3">{@label}</.label>
      <%!-- The directory every file shares, printed once so the names below
          are names. On the rail, like the label above it and the rows below
          it — a card has two left edges, never three (§3). --%>
      <p :if={@common != ""} class="font-mono truncate pl-3 text-xs text-zinc-500">{@common}/</p>
      <div class="max-h-64 overflow-y-auto pr-2">
        <ul class="space-y-0.5 pt-1">
          <li :for={file <- @files} class="font-mono truncate pl-3 text-xs text-zinc-400">
            {file_label(file, @common)}
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp common_dir([]), do: ""

  defp common_dir(files) do
    files
    |> Enum.map(&Path.split(Path.dirname(&1)))
    |> Enum.reduce(fn segments, acc ->
      acc
      |> Enum.zip(segments)
      |> Enum.take_while(fn {a, b} -> a == b end)
      |> Enum.map(&elem(&1, 0))
    end)
    |> case do
      [] -> ""
      segments -> Path.join(segments)
    end
  end

  defp file_label(file, ""), do: file
  defp file_label(file, common), do: Path.relative_to(file, common)

  attr :title, :string,
    default: nil,
    doc: "omit where the section is the form's subject and the page title already says it"

  attr :id, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  @doc """
  A named run of field groups, for a form long enough to need finding your
  way around — the import form's anatomy, which is where this came from.

  Headings sit on the ground with no rule under them; the 56px section gap
  and the blocks below do the dividing (§1, §3).

  The heading is optional, because a form's *first* section is usually the
  thing the form is about and naming it says nothing: the audiobook form
  opened with "The audiobook" under a page already titled with the
  audiobook's name. The book and person forms never had one. A section
  still earns a heading when it is a genuine change of subject — "Chapters",
  "Audio and processing".
  """
  def form_section(assigns) do
    ~H"""
    <section id={@id} class={["space-y-7", @class]}>
      <h2 :if={@title} class="text-xl font-bold text-zinc-100">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :field, FormField,
    default: nil,
    doc: "an `inputs_for` sort field — supply it and the button drives Ecto's sort-param trick"

  attr :navigate, :string,
    default: nil,
    doc: "for a section whose add is a page — the locations page's two"

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @doc """
  Adds one more row to a list the operator is building.

  **One costume for this job across the whole admin.** It was three: a
  brand-colored link with a plus on the legacy forms, a lime "New +" on every
  list header, and this — three answers to "add another one of these" on
  three surfaces the operator moves between, and the import form's is the
  one that was right.

  Deliberately NOT the raised action costume Confirm and Split wear: adding
  a blank row is the least consequential thing on a form, and a row of pills
  competes with the decisions above it (tried, and rejected by the operator
  on sight). Its box sits on the container edge like every other control,
  and `px-3` lands its label on the text rail — a control whose box was
  nudged onto the rail put its text at a third x-position nothing else
  shares, which read as misalignment on every form (§3: text lands on the
  rail exactly, wherever it lives).

  Two call styles, because the legacy forms add a row by posting a sort
  param and the import form does it with an event: pass `field` for the
  former, `phx-click` for the latter.
  """
  def add_button(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link navigate={@navigate} class={add_button_classes(@class)} {@rest}>
      <.icon name="fa-plus" class="h-3 w-3 flex-none text-current" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def add_button(assigns) do
    ~H"""
    <button
      type="button"
      name={@field && @field.name <> "[]"}
      value={@field && "new"}
      phx-click={@field && JS.dispatch("change")}
      class={add_button_classes(@class)}
      {@rest}
    >
      <.icon name="fa-plus" class="h-3 w-3 flex-none text-current" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  # **Dimmer than a real action, on purpose.** Confirm, Split and the queue's
  # row actions are raised opaque fills; adding a blank row is the least
  # consequential thing on a form, so it is the faintest fill that still
  # reads as a control. `ml-3` puts its box on the text rail: a small pill
  # that isn't a field is content, not a container, and sits where an image
  # would (§3).
  defp add_button_classes(extra) do
    [
      "bg-white/5 inline-flex w-fit cursor-pointer items-center gap-1.5 rounded-md px-3 py-1",
      "text-xs font-semibold text-zinc-300 transition-colors hover:bg-white/10 hover:text-zinc-100",
      extra
    ]
  end

  attr :field, FormField, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  def import_form_row(assigns) do
    ~H"""
    <div class="flex gap-4 rounded-sm p-3 hover:bg-zinc-950">
      <div class="py-1">
        <.input type="checkbox" field={@field} />
      </div>
      <label for={@field.id} class="grow cursor-pointer space-y-2">
        <span class="text-sm font-semibold leading-6 text-zinc-200">
          {@label}
        </span>
        {render_slot(@inner_block)}
      </label>
    </div>
    """
  end

  @doc """
  Book Card for displaying normalized metadata-provider results.
  """
  attr :book, :any, required: true
  slot :actions

  def book_card(%{book: %Ambry.Metadata.Provider.Book{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img
        :if={@book.cover_url}
        src={proxied_remote_image_url(@book.cover_url)}
        class="h-24 w-24 object-contain object-top"
      />
      <div>
        <p class="font-bold">{@book.title}</p>
        <p :if={@book.authors != []} class="text-zinc-400">
          <span :for={author <- @book.authors} class="group">
            <span>{author.name}</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.narrators != []} class="text-zinc-400">
          Read by
          <span :for={narrator <- @book.narrators} class="group">
            <span>{narrator.name}</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.series != []} class="text-xs text-zinc-400">
          <span :for={series <- @book.series} class="group">
            <span>{series.name} #{series.number}</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.published} class="text-xs text-zinc-400">
          Published {display_date(@book.published)}<span :if={@book.publisher}> by {@book.publisher}</span>
        </p>
        <p :if={@book.format} class="text-xs text-zinc-400">{@book.format}</p>
        <div :for={action <- @actions}>
          {render_slot(action)}
        </div>
      </div>
    </div>
    """
  end

  def display_date(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")

  def display_date(%Ambry.Metadata.Provider.PublishedDate{display_format: :full, date: date}),
    do: Calendar.strftime(date, "%B %-d, %Y")

  def display_date(%Ambry.Metadata.Provider.PublishedDate{
        display_format: :year_month,
        date: date
      }), do: Calendar.strftime(date, "%B %Y")

  def display_date(%Ambry.Metadata.Provider.PublishedDate{display_format: :year, date: date}),
    do: Calendar.strftime(date, "%Y")

  def multi_image(%{paths: []} = assigns) do
    ~H"""
    <div class="h-16 w-16 bg-zinc-800" />
    """
  end

  def multi_image(%{paths: [path]} = assigns) do
    assigns = assign(assigns, :path, path)

    ~H"""
    <div class="h-16 w-16">
      <img src={@path} class="h-full w-full" />
    </div>
    """
  end

  def multi_image(%{paths: [path1, path2]} = assigns) do
    assigns = assign(assigns, %{path1: path1, path2: path2})

    ~H"""
    <div class="relative h-16 w-16">
      <img src={@path2} class="translate-x-[2px] translate-y-[2px] absolute top-0 left-0 h-full w-full scale-95" />
      <img
        src={@path1}
        class="-translate-x-[2px] -translate-y-[2px] absolute top-0 left-0 h-full w-full scale-95 border border-zinc-800 shadow-md"
      />
    </div>
    """
  end

  def multi_image(%{paths: [path1, path2, path3 | _rest]} = assigns) do
    assigns = assign(assigns, %{path1: path1, path2: path2, path3: path3})

    ~H"""
    <div class="relative h-16 w-16">
      <img src={@path3} class="absolute top-0 left-0 h-full w-full translate-x-1 translate-y-1 scale-90" />
      <img
        src={@path2}
        class="absolute top-0 left-0 h-full w-full scale-90 border border-zinc-800 shadow-md"
      />
      <img
        src={@path1}
        class="absolute top-0 left-0 h-full w-full -translate-x-1 -translate-y-1 scale-90 border border-zinc-800 shadow-md"
      />
    </div>
    """
  end
end
