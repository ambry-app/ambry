defmodule AmbryWeb.Admin.Components do
  @moduledoc false

  use AmbryWeb, :html

  import Ambry.Utils, only: [humanize_bytes: 1, name_credit: 1, series_credit: 1]
  import AmbryWeb.Gravatar
  import AmbryWeb.TimeUtils, only: [duration_display: 1, format_timecode: 1]

  alias Ambry.Accounts.User
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField

  attr :user, User, required: true
  attr :title, :string, required: true
  # The header hosts a nested LiveView, which needs the parent socket to
  # mount into. Required rather than defaulted, so a page that forgets it is
  # a compile warning rather than a page silently missing the indicator.
  attr :socket, Phoenix.LiveView.Socket, required: true

  slot :inner_block, required: true
  slot :subheader

  def layout(assigns) do
    ~H"""
    <div class="min-w-0">
      <.layout_header user={@user} title={@title} socket={@socket}>
        {render_slot(@subheader)}
      </.layout_header>

      <%!-- The document is the scrollport, not this element: LiveView
            restores `window.scrollY` and nothing else, so an
            `overflow-y-auto` here would cost the admin its scroll position on
            every navigation. The id and the `p-4` stay, because the
            sticky-footer hook and §3's arithmetic both name them.

            No horizontal overflow guard, deliberately: `hidden` forces the
            other axis to `auto` and makes this a scrollport again, and `clip`
            puts a clipping ancestor between every sticky bar and the
            viewport. A horizontal scrollbar is the signal to apply §3's
            `min-w-0` rule to whatever is wide. --%>
      <main id="main-content" class="p-4">
        {render_slot(@inner_block)}
      </main>

      <%!-- Telling two records apart sometimes takes the full-size art.
          Opened by any [data-zoomable] magnifier (see app.js);
          `phx-update="ignore"` because it is pure client state. --%>
      <div
        id="image-lightbox"
        phx-update="ignore"
        class="bg-black/85 z-[90] fixed inset-0 hidden cursor-zoom-out items-center justify-center p-8 backdrop-blur"
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

  # **The z-index ladder for the whole admin.** One list, here, because
  # content scrolls under the chrome and almost all of this shares the root
  # stacking context: an `index_row` is `relative` with no z-index of its own,
  # so its layers compete directly with the page's chrome.
  #
  #   10   the clickable layer inside a card (a row's action rail)
  #   20   a busy scrim over a single card
  #   30   the sticky page footers — `sticky_slab_classes/0`
  #   35   a typeahead's popup: clear of the sticky footer it may open over,
  #        under the scrims that mean the form is not yours right now
  #   40   a page-wide busy scrim (`busy_overlay/1` at `scope={:form}`), which
  #        has to cover the Save button or it is only advisory
  #   50   this header, and the public one
  #   60   the drawer's scrim
  #   70   the side nav drawer
  #   80   a modal — it covers the viewport, and the nav is part of what it is
  #        covering, so it sits above the nav rather than beside it
  #   90   the image lightbox, which opens from inside a modal's content
  #   100  flash toasts, which are the one thing that outranks everything
  #
  # Gaps in the tens are deliberate: a new layer needs somewhere to go.
  #
  # A tie is not a tie: equal z-index falls back to DOM order, and page
  # content always comes after the header, so anything that must stay above
  # the page needs a strictly greater number.
  defp layout_header(assigns) do
    ~H"""
    <header
      id="nav-header"
      phx-hook="header-scrollspy"
      class="sticky top-0 z-50 space-y-4 border-zinc-900 bg-zinc-950 p-4"
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
        <%!-- A LiveView of its own, not a component: it polls, and a poll on
              the page's socket makes the page re-render every tick. Sticky so
              a live navigation doesn't blink the spinner off mid-job. --%>
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

  Moving *through* a list is `pagination_footer/1`, under the last row: the
  header does not move, so a "next page" up here would land the operator at
  the bottom of the page they just asked for.
  """
  def list_controls(assigns) do
    ~H"""
    <div class="flex items-end gap-4">
      <%!-- The attr is optional, so the form has to be too: a short list
            that is never searched still wants the New button, and the grow
            div stays either way so the button keeps its corner. --%>
      <div class="grow">
        <.admin_table_search_form :if={@search_form} search_form={@search_form} />
      </div>
      <%!-- A list page's one constructive action, so it wears §6's primary
            costume: a text link in this slot reads as navigation rather than
            as the thing the page is for. --%>
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
        <%!-- The app-standard fill, like every other control: the one input
              on a list page should not look unlike every input on the page it
              leads to. --%>
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

  In `form_footer/1`'s costume, because it is the same object doing the same
  job. Sticky rather than merely in the flow, since a page is two or three
  screens.
  """
  def pagination_footer(assigns) do
    ~H"""
    <div
      :if={@has_prev or @has_next}
      id="pagination"
      phx-hook="sticky-footer"
      class={[sticky_slab_classes(), "mt-3 -mb-4 flex flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3"]}
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

  # Worded, like every other action in this admin (§3a). An unavailable step
  # is present and dead rather than absent, so the bar keeps its shape at
  # both ends of the list.
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
  says. A row's anatomy is `index_row/1`.
  """
  attr :id, :string, default: "list", doc: "the list-scroll-reset hook needs one"
  attr :rows, :list, required: true
  attr :filter, :string, default: nil

  attr :list_state, :any,
    default: nil,
    doc: "what identifies this view (page, filter, sort). A change scrolls back to the top."

  attr :focus, :any,
    default: nil,
    doc: "a record to scroll to and light up, named by a form the operator is returning from"

  slot :empty
  slot :row, required: true

  def flex_table(assigns) do
    ~H"""
    <%!-- The hook lives out here rather than on the rows, so it survives a
          filter that empties the list and is still mounted when the next one
          fills it again. --%>
    <div id={@id} phx-hook="list-scroll-reset" data-list-state={inspect(@list_state)}>
      <%!-- A second hook needs a second element; they are different jobs on
            the same list and the scroll reset must not fire for a focus. --%>
      <div id={"#{@id}-focus"} phx-hook="focus-row" data-focus={@focus} class="hidden" />
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

  **The whole card is the link, and it is a real one.** The headline is an
  `<a>` whose `::after` covers the card: a card-sized target that still takes
  focus, a middle click and open-in-new-tab.

  Everything clickable sits in a `z-10` layer above that pseudo-element; the
  busy overlay is `z-20` and covers both.

  Each slot has exactly one home:

    * `:cover` — `row_cover/1`, at the card's left edge.
    * `:headline` — the title. Always the link, always `font-semibold`.
    * `:inner_block` — the credit stack and meta lines.
    * `:badges` — state, top of the right rail, on the headline's baseline.
    * `:facts` — the glyph-and-count strip, folding into the card on a phone.
    * `:action` — one entry per verb, worded, never icon-only.
    * `:footer` — **system timestamps only**. A publication date and a
      duration are facts about the work, so they go on the meta line.

  **The rail is 224px, two buttons wide, and actions wrap** into two rows of
  two. The constraint falls on the labels: short enough that two fit.
  """
  attr :record_id, :any,
    default: nil,
    doc:
      "the row's record, so a form can send the operator back to it (see `AmbryWeb.Admin.ReturnTo`)"

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
      id={@record_id && "row-#{@record_id}"}
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
                  stays an ordinary inline element and only its pseudo-element
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

      <%!-- The rail's corners share the card's baselines. `self-stretch` is
            load-bearing, or the column is content-height and
            `justify-between` does nothing. --%>
      <div
        :if={[@badges, @facts, @action, @footer] != [[], [], [], []]}
        class="relative z-10 flex w-full flex-none flex-wrap items-center gap-x-3 gap-y-2 sm:w-56 sm:flex-col sm:items-end sm:justify-between sm:self-stretch"
        inert={@inert}
      >
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5 sm:flex-col sm:items-end">
          <%!-- The rail sets the badge size, rather than every caller
                remembering to. Callers passing `text-xs` are harmless. --%>
          <div :if={@badges != []} class="flex flex-wrap items-center gap-1.5 text-xs">
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

          <%!-- Content-sized and right-aligned, never one fixed width per
                rail, which would force the longest label anywhere in the
                admin onto every "Edit". Which layout applies is decided by
                the number of verbs, never by what fits. --%>
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
  The one dash §8 leaves standing: a cell with no value in it.

  It has one home so it stays the only one. `AmbryWeb.VoiceTest` allows a
  string that is *nothing but* the dash, which is exactly this.
  """
  def empty_value, do: "\u2014"

  attr :on, :boolean, required: true
  attr :attention, :boolean, default: false, doc: "amber rather than dim: on, but behind"

  @doc """
  The ambient state of a thing that is either running or not.

  §6b's rule wearing one costume: an indicator renders its quiet state too,
  so the dot is always there and only its colour moves.
  """
  def status_dot(assigns) do
    ~H"""
    <span class={[
      "inline-block h-2.5 w-2.5 flex-none rounded-full",
      @on && "bg-lime-500",
      !@on && @attention && "bg-amber-500",
      !@on && !@attention && "bg-zinc-600"
    ]} />
    """
  end

  attr :src, :string, default: nil, doc: "nil renders the empty box, never a broken image"

  attr :shape, :atom,
    default: :cover,
    doc: ":cover for a book or a recording, :face for a person"

  @doc """
  The image at a row's left edge, in the one 64px box every list shares.

  **A row whose record has an image shows it** (§3a), and one whose record
  has none shows the empty box rather than collapsing, so headlines stay on
  one rail.

  A remote URL is proxied here, not by the caller (§7), since
  `proxied_remote_image_url/1` leaves a local path alone.
  """
  def row_cover(assigns) do
    ~H"""
    <div class={[
      "h-16 w-16 overflow-hidden",
      @shape == :face && "rounded-full",
      @shape == :cover && "rounded-sm",
      !@src && "bg-zinc-800"
    ]}>
      <img
        :if={@src}
        src={proxied_remote_image_url(@src)}
        alt=""
        class={["h-full w-full object-cover", @shape == :face && "object-top"]}
      />
    </div>
    """
  end

  @doc """
  The credit stack's own lines: bare author names, then the narrators muted.

  The part every record has, which is what lets a row be three fixed lines
  and one variable one. Names join with commas and nothing is prefixed with
  "by" (§8); "Read by" stays, because an unlabelled list reads as authors.
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

  **Three fixed lines, then this one.** Title, authors and narrators are what
  every record has; series, publisher, published and duration are each
  sometimes there, so they share the fourth and it collapses to nothing.

  With the credits rather than in the rail, because it is prose. Takes either
  flat view.
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
  event. `:red` reveals the danger fill on hover rather than wearing it, so a
  row of actions doesn't read as a row of warnings (§6).
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
  # `disabled:` variants need a `:disabled` pseudo-class, which a `<span>`
  # can never match, so the refusing state is spelled out and the click
  # binding is dropped: `pointer-events-none` stops a mouse and nothing else.
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

  attr :scope, :atom,
    default: :card,
    values: [:card, :form],
    doc: "how much it covers, which decides both its layer and where its label sits"

  attr :rest, :global

  @doc """
  Covers whatever it sits in while a background job owns it.

  A form whose draft is about to be rebuilt under the operator looks exactly
  like one waiting for them to type in it, and matching retries for minutes.
  A scrim over the whole thing, not a badge in a corner: the point is that
  this is not yours right now.

  Must sit inside a `relative` container. It swallows clicks by covering them;
  `inert` on the content beside it stops keyboard focus, and the LiveView
  refuses the events anyway.

  Two scopes, named rather than passed in. `:card` covers one block at z-20.
  `:form` covers a whole form at z-40, above the sticky footer, since a scrim
  that leaves Save clickable is only advisory; it keeps its label in a
  `sticky top-0 h-screen` child so the message stays centred on screen.
  """
  def busy_overlay(assigns) do
    ~H"""
    <div
      :if={@busy}
      class={[
        "bg-zinc-950/70 backdrop-blur-[1px] absolute inset-0 rounded-lg",
        @scope == :card && "z-20 flex items-center justify-center gap-2",
        @scope == :form && "z-40"
      ]}
      data-role="busy-overlay"
      aria-live="polite"
      {@rest}
    >
      <div class={@scope == :form && "sticky top-0 flex h-screen items-center justify-center gap-2"}>
        <.icon name="fa-rotate" class="h-4 w-4 animate-spin text-zinc-300" />
        <span class="text-sm font-semibold text-zinc-200">{@label}</span>
      </div>
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

  Browsers place the native summary marker where they like and `inside`
  pushes the summary text off the rail, so it is hidden and the chevron drawn
  by hand.
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
    <%!-- ✕, not a trash can: removing a row is undoable until save, and two
        costumes for one gesture read as two gestures (§6).

        Beside the field, never inside one: the gesture removes the row, not
        the field's value, and a mark inside a box belongs to that box.

        Exactly one input tall with its glyph centred, so it lines up by being
        the same height rather than by a hand-picked `mt-3` (§7). --%>
    <button
      type="button"
      name={@field.name <> "[]"}
      value={@index}
      phx-click={JS.dispatch("change")}
      class={["flex h-10 flex-none items-center", @class]}
    >
      <.icon name="fa-xmark" class="h-4 w-4 cursor-pointer text-current transition-colors hover:text-red-400" />
    </button>
    """
  end

  @doc """
  Carries a row's place in the list back to the server.

  Not decoration: `cast_assoc` returns `:ignore` when every child changeset
  comes back empty, so a reorder that changes no field is invisible to Ecto.
  See `AmbryWeb.Admin.Reordering`.
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

  The button at each end is disabled rather than hidden, so the controls do
  not shift horizontally as rows move past them.

  **These send no event.** The `reorder-rows` hook on the form swaps two
  hidden inputs and dispatches a change. A form holding one needs
  `phx-hook="reorder-rows"`; the count comes from
  `AmbryWeb.Admin.Reordering.row_count/2`.
  """
  attr :field, :atom, required: true, doc: "the association field being reordered"
  attr :index, :integer, required: true
  attr :count, :integer, required: true
  attr :class, :string, default: nil

  def move_buttons(assigns) do
    ~H"""
    <%!-- Exactly one input tall (`py-[7px]` + `leading-6` + the transparent
        border = 40px) with its glyphs centred, so it lines up with the field
        it reorders by being the same height as it (§7). A hand-picked `mt-3`
        at each call site lands short and slides off entirely as soon as the
        row carries an error or a second control. --%>
    <div class={["flex h-10 flex-none flex-col justify-center", @class]} data-role="move-buttons">
      <button
        type="button"
        data-move="up"
        data-move-field={@field}
        data-move-index={@index}
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
        data-move="down"
        data-move-field={@field}
        data-move-index={@index}
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

  A cluster is the unit: the fields answering one question about the record
  ("who wrote it", "where it lives"), on the zinc-900 block every other
  decision in this admin sits on.

  The label names the cluster and sits on the text rail (§3). Fields that
  speak for themselves need none: the block and its spacing are the grouping.
  """
  def field_group(assigns) do
    ~H"""
    <%!-- **A block holds the whole cluster: its name, its rows, and the way to
        add one.** The import form is the other shape, where each row is its
        own decision card and the label and add sit on the ground around the
        run. Same costumes either way. --%>
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
  A list the operator is building, in the one grammar every form shares:
  **the card names itself** (label, provenance flag and hint at the top of the
  container, on the rail), rows follow, the add sits below the container on
  the ground.

  Ground level is for section headings and helper prose only; everything a
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

  @doc """
  The costume a bar wears when it is pinned to the bottom of the page.

  Two of them, `form_footer/1` and `pagination_footer/1`, stated once so they
  cannot drift.

  `bottom-0` because a sticky box is positioned against its scrollport and the
  viewport has no padding. `-mb-4` is the other half: a sticky box cannot
  leave its containing block, so without it the block's bottom edge holds the
  bar 16px up at the end of the scroll. A form wears that negative margin on
  its content wrapper; the pagination bar wears it itself.
  """
  def sticky_slab_classes do
    "shadow-[0_-12px_32px_rgba(0,0,0,0.55)] sticky bottom-0 z-30 rounded-t-lg bg-zinc-900"
  end

  attr :id, :string, default: "form-footer", doc: "the sticky-footer hook needs one"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  slot :danger,
    doc: "destroying the record this form edits, pushed to the far end of the bar (§6)"

  @doc """
  The sticky footer slab every form's actions sit in.

  One costume for "where a form is saved": a shadowed `zinc-900` slab, never a
  bare button on the ground after the last card, which on a long form is at
  the bottom of the scroll. See `sticky_slab_classes/0` for the offsets.

  **The `:danger` slot is where a record is destroyed**, one of the two homes
  a delete has (§6). It sits at the far end, with the width of the bar between
  it and Save.
  """
  def form_footer(assigns) do
    ~H"""
    <%!-- The sticky-footer hook rounds the bottom corners (and drops the
        floating shadow) whenever the page has nothing to scroll — a slab
        that never sticks is an ordinary card and dresses like one. --%>
    <section id={@id} phx-hook="sticky-footer" class={[sticky_slab_classes(), "p-4", @class]} {@rest}>
      <div class="flex flex-wrap items-center gap-2">
        {render_slot(@inner_block)}

        <%!-- The whole width of the bar between Save and this one, so the
            irreversible thing is never adjacent to the thing pressed every
            time. --%>
        <div :if={@danger != []} class="ml-auto">{render_slot(@danger)}</div>
      </div>
    </section>
    """
  end

  attr :source, :any, required: true, doc: "the `Ambry.Library.Source` an item was found in"
  attr :class, :any, default: nil

  @doc """
  Which watched folder an inbox item came from.

  One tint for every source: they are told apart by name, and colouring them
  apart would invent a taxonomy the model does not have. What import will *do*
  with the files is a per-import decision, stated on the item's destination
  card and deliberately not here.
  """
  def source_tag(assigns) do
    ~H"""
    <.place_tag name={@source.name} class={@class} />
    """
  end

  attr :root, :any, required: true, doc: "the `Ambry.Library.Root` the files live in"
  attr :class, :any, default: nil

  @doc """
  Which library root a recording's files live in.

  The same costume as `source_tag/1`, because it answers the same question
  about the same list of files: where these are. A watched folder and a
  library root are different things, but "where" is one fact and two tints
  for it would say there are two kinds of answer.
  """
  def root_tag(assigns) do
    ~H"""
    <.place_tag name={@root.name} class={@class} />
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: nil

  # Blue is location (§5), and there is one tint for every place: they are
  # told apart by name, and colouring them apart would invent a taxonomy the
  # model doesn't have.
  defp place_tag(assigns) do
    ~H"""
    <span
      class={["bg-blue-400/15 rounded-sm px-1 py-0.5 text-xs text-blue-300", @class]}
      data-role="place"
    >
      {@name}
    </span>
    """
  end

  attr :files, :list, required: true
  attr :label, :string, default: nil, doc: "the card names itself — rendered inside, on the rail"

  attr :excluded, :list,
    default: [],
    doc: "files that are listed but not part of the thing: struck through, and counted"

  attr :toggle, :string,
    default: nil,
    doc: "phx-click event taking a file in or out; without it the list is a fact display"

  attr :card, :boolean,
    default: true,
    doc: "false where the caller is already a card — a card in a card eats the ladder (§1)"

  attr :class, :any, default: nil

  slot :tag, doc: "where these files are, beside the label — a source or a library root"

  @doc """
  A read-only list of files: mono, muted, the common directory printed once.

  This is a fact display, not a control, so it deliberately does not wear the
  dashed dropzone costume (§1): "the files you have" must not look like a
  place to drop more.

  Long lists scroll *inside* the card, with the label and common-directory
  line pinned and the scrollbar in its own gutter (`pr-2`).

  Given `toggle`, each row grows the list-row remove (§6's ✕), and an excluded
  file **stays in the list**, struck through with the way back beside it:
  hidden, the card would disagree with the folder it describes. The count line
  appears only when something is out.
  """
  def file_list(assigns) do
    assigns = assign(assigns, :common, common_dir(assigns.files))

    ~H"""
    <div :if={@files != []} class={["space-y-1", @card && "rounded-lg bg-zinc-900 p-4", @class]}>
      <div class="flex items-baseline justify-between gap-3 pl-3" data-role="files-header">
        <%!-- Label and place read as one fact, so they share the left of the
            line and the count keeps the right. --%>
        <div class="flex min-w-0 items-baseline gap-2">
          <.label :if={@label}>{@label}</.label>
          {render_slot(@tag)}
        </div>
        <p :if={@excluded != []} class="flex-none text-xs text-zinc-400" data-role="excluded-count">
          {length(@files) - length(@excluded)} of {length(@files)} in this audiobook
        </p>
      </div>
      <%!-- The directory every file shares, printed once so the names below
          are names. On the rail, like the label above it and the rows below
          it — a card has two left edges, never three (§3). --%>
      <p :if={@common != ""} class="font-mono truncate pl-3 text-xs text-zinc-500">{@common}/</p>
      <div class="max-h-64 overflow-y-auto pr-2">
        <ul class="space-y-0.5 pt-1">
          <%!-- The row lights up as a whole: the control is at the far edge of a
              wide card and the name at the near one, so nothing else joins
              them. Only where there is something to click. --%>
          <li
            :for={file <- @files}
            class={["group flex items-baseline gap-2 rounded-sm py-0.5 pl-3 text-xs", @toggle && "hover:bg-white/5"]}
            data-role={file in @excluded && "excluded-file"}
          >
            <span class={[
              "font-mono min-w-0 truncate",
              if(file in @excluded, do: "text-zinc-500 line-through", else: "text-zinc-400")
            ]}>
              {file_label(file, @common)}
            </span>

            <span :if={file in @excluded} class="flex-none text-zinc-500">not in this audiobook</span>

            <button
              :if={@toggle}
              type="button"
              phx-click={@toggle}
              phx-value-file={file}
              class="ml-auto flex-none rounded-sm px-1 text-zinc-500 hover:bg-white/10 hover:text-zinc-100 group-hover:text-zinc-300"
              title={if file in @excluded, do: "Put this file back", else: "Not part of this audiobook"}
              aria-label={if file in @excluded, do: "Put this file back", else: "Not part of this audiobook"}
            >
              <.icon name={if file in @excluded, do: "fa-rotate-left", else: "fa-xmark"} class="h-3 w-3 text-current" />
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @doc """
  What the probe found, as facts to read along one line.

  One list for every surface that describes a set of files, so two of them
  cannot count differently. Where a surface puts the count is the one thing
  they may disagree about, which is what `:files` is for.

  **Size and bitrate together are the fact**: two copies of one audiobook can
  be the same recording at half the rate, which only the second number shows.
  """
  def probe_facts(probe, opts \\ [])

  def probe_facts(probe, opts) when is_map(probe) do
    [
      probe["duration"] && format_timecode(Decimal.new(probe["duration"])),
      Keyword.get(opts, :files, false) && file_count(probe),
      probe["size"] && humanize_bytes(probe["size"]),
      bitrate(probe),
      probe["codec"],
      probe["chapters"] && probe["chapters"] > 0 && "#{probe["chapters"]} chapters",
      probe["seek_accuracy"] == "approximate" && "inexact seeking"
    ]
    |> Enum.filter(&is_binary/1)
  end

  def probe_facts(_probe, _opts), do: []

  # The average over the whole recording, which is the only rate worth
  # comparing: a multi-file release is one timeline, and a list of per-file
  # rates cannot be held against another list. Rounded to whole kbps because
  # the question this answers is "64 or 127", never "63.5 or 63.6".
  defp bitrate(%{"size" => size, "duration" => duration}) when is_integer(size) do
    with %Decimal{} = seconds <- probe_seconds(duration),
         true <- Decimal.positive?(seconds) do
      "#{round(size * 8 / Decimal.to_float(seconds) / 1000)} kbps"
    else
      _not_measurable -> nil
    end
  end

  defp bitrate(_probe), do: nil

  # jsonb hands the duration back as a string; a struct reaches here only
  # from a caller that already parsed it.
  defp probe_seconds(%Decimal{} = seconds), do: seconds

  defp probe_seconds(seconds) when is_binary(seconds) do
    case Decimal.parse(seconds) do
      {decimal, ""} -> decimal
      _unparseable -> nil
    end
  end

  defp probe_seconds(_other), do: nil

  # A one-file recording says nothing; a forty-file one is the single most
  # useful fact about it, because it is what the timeline is built out of.
  defp file_count(%{"files" => count}) when is_integer(count) and count > 1, do: "#{count} files"
  defp file_count(_probe), do: nil

  @doc """
  The directory every one of these files shares.

  Public because a caller sometimes needs to know what this card is about to
  say: the inbox form prints the item's path above it and drops that line
  when the list is going to state the same thing (`stated_by_files?/1`). Two
  answers to "where is this" would have to agree, so there is one.
  """
  def common_dir([]), do: ""

  def common_dir(files) do
    files
    |> Enum.map(&folder_segments/1)
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

  # A file with no directory above it has no directory *line*: `Path.dirname`
  # answers "." for a path that is just a name, and the card was printing
  # "./" over the loose files at the top of a watched folder.
  defp folder_segments(file) do
    case Path.dirname(file) do
      "." -> []
      dir -> Path.split(dir)
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

  slot :action,
    doc: "a control for the section as a whole, on the heading's line at its right edge"

  slot :blurb, doc: "helper prose under the heading, on the ground (§3b)"

  @doc """
  A named run of field groups, for a form long enough to need finding your way
  around. Headings sit on the ground with no rule under them; the 56px section
  gap and the blocks below do the dividing (§1, §3).

  The heading is optional: a form's first section is usually the thing the
  form is about, and naming it says nothing under a page already titled with
  it. A section earns a heading when it is a genuine change of subject.
  """
  def form_section(assigns) do
    ~H"""
    <section id={@id} class={["space-y-7", @class]}>
      <%!-- The heading stays on the ground with nothing under it; a control
          for the whole section sits at the other end of its line, which is
          where the list clusters put theirs. --%>
      <div :if={@title || @action != []} class="space-y-2">
        <div class="flex items-baseline justify-between gap-4">
          <h2 :if={@title} class="text-xl font-bold text-zinc-100">{@title}</h2>
          <div :if={@action != []} class="flex-none">{render_slot(@action)}</div>
        </div>

        <p :if={@blurb != []} class="text-sm text-zinc-400">{render_slot(@blurb)}</p>
      </div>
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

  **One costume for this job across the whole admin.** Deliberately not the
  raised action costume: adding a blank row is the least consequential thing
  on a form, and a row of pills competes with the decisions above it. Its box
  sits on the container edge and `px-3` lands the label on the rail; nudging
  the *box* onto the rail puts its text at a third x-position (§3).

  Two call styles: pass `field` for a form built on `inputs_for`, `phx-click`
  for one driven by events.
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
