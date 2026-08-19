defmodule AmbryWeb.Components.EntityDropdown do
  @moduledoc """
  The plain drop-down: click it, see what there is, click one.

  A sibling of `AmbryWeb.Components.EntityResolver` and deliberately almost
  its twin to look at — same trigger, same list flush below it, same rows
  (both draw `AmbryWeb.Components.EntityOption.option_row/1`). The difference
  is that there is nothing to type into and nothing to search: the options
  arrive with the component.

  ## Why this exists

  A typeahead is the right control when the answer is one of hundreds and the
  operator knows roughly what it is called. It is the wrong control when the
  answer is one of three. The set picker on an audiobook form offers that
  book's sets — usually one — and the member picker on a set form offers that
  book's audiobooks, usually two or three. Asking someone to type a name to
  narrow a list of two, and to remember what the two are called before the
  list will show them, is a search box standing in for a menu.

  A native `<select>` would be the honest control for that, and is not usable
  here: these options carry a cover and a second line ("2 of 3 parts"), which
  a browser's option list cannot render, and its menu is drawn by the OS, so
  the two pickers on one form would not look like each other.

  ## What it is given

      options={[%{id: 1, label: "The Expanse", image: "/x.webp", detail: "2 of 3 parts"}]}
      value={@form[:recording_group_id].value}

  All the options, up-front, in the order they should be read. There is no
  `search` and no `fetch`: the held record is in the list by construction,
  which is most of what makes this the simpler control.

  No `prompt` either, deliberately. A `<select>`'s prompt is also its clear
  row, and neither caller wants one: emptying these fields is the ✕ beside
  them, which removes the row rather than blanking the field. Adding one
  before something needs it would mean two ways to say the same thing.

  ## Talking to the form

  Same contract as the resolver, and the same hooks: a hidden input carries
  the answer, every interaction is handled server-side, and `moved/1` pushes
  `entity-resolver:moved` so the `entity-resolver-input` hook can fire the
  `input` event a native control would have. See that component's moduledoc
  for why the answer travels in the event rather than being read off the DOM.
  """

  use AmbryWeb, :live_component

  import AmbryWeb.Components.EntityOption

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assigns
      |> assign(:options, Enum.map(assigns.options, &normalize/1))
      |> then(&assign(&1, :held, Enum.find(&1.options, fn o -> selected?(o, &1.value) end)))
      |> then(&assign(&1, :imaged, Enum.any?(&1.options, fn o -> o.image end)))

    ~H"""
    <div
      id={@id}
      class="relative min-w-0 flex-grow"
      phx-hook="combobox-nav"
      phx-click-away={@open && JS.push("close", target: @myself)}
    >
      <input
        type="hidden"
        id={"#{@id}-value"}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value("hidden", @value)}
        data-resolver={@id}
        phx-hook="entity-resolver-input"
      />
      <%!-- A button rather than a styled div: it is one tab stop, it opens on
          Enter and Space without being taught to, and `combobox-nav` finds it
          by the same `role=combobox` the resolver's text input wears. --%>
      <button
        type="button"
        id={"#{@id}-trigger"}
        role="combobox"
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-list"}
        phx-click={JS.push("toggle", target: @myself)}
        class={[@class, "flex items-center gap-2 pr-8 text-left"]}
      >
        <%!-- The fallback is a non-breaking space, not "". An empty inline
            span is a flex item with no line box, so a drop-down holding
            nothing collapsed to its own padding and stood two-thirds the
            height of the field beside it. One space of text reserves exactly
            what text would, at whatever size and leading the breakpoint is
            using — which a `min-h-*` guess cannot promise. --%>
        <span class="min-w-0 truncate">
          {(@held && @held.label) || "\u00A0"}
        </span>
        <%!-- The one thing that tells this apart from the resolver at a
            glance, which is the point: a text box invites typing and this
            does not. --%>
        <.icon
          name="fa-chevron-down"
          class="absolute top-1/2 right-3 h-3 w-3 -translate-y-1/2 text-zinc-500"
        />
      </button>
      <%!-- Flush against the trigger, `z-[35]` on the ladder in
          `AmbryWeb.Admin.Components.layout_header/1` — both copied from the
          resolver on purpose. Two controls this alike must not open two
          different-looking lists. --%>
      <ul
        :if={@open}
        id={"#{@id}-list"}
        role="listbox"
        class="min-w-48 z-[35] absolute max-h-64 w-full overflow-auto rounded-b-md bg-zinc-800 text-sm shadow-xl"
      >
        <li
          :for={option <- @options}
          id={"#{@id}-option-#{option.id}"}
          role="option"
          aria-selected={to_string(selected?(option, @value))}
          phx-click="pick"
          phx-value-id={option.id}
          phx-target={@myself}
          class={[
            "cursor-pointer px-3 py-2 data-[active]:bg-zinc-700 hover:bg-zinc-700",
            selected?(option, @value) && "bg-white/5"
          ]}
        >
          <.option_row option={option} selected={selected?(option, @value)} imaged={@imaged} />
        </li>
        <li :if={@options == []} class="px-3 py-2 text-zinc-500">
          Nothing to choose from
        </li>
      </ul>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, open: false)}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:value, fn -> nil end)
     |> assign_new(:class, fn -> nil end)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, open: !socket.assigns.open)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def handle_event("pick", params, socket) do
    {:noreply,
     socket
     |> assign(value: params["id"], open: false)
     |> moved()}
  end

  # Same signal, same hook, same reason as the resolver's: the form is told
  # this moved, rather than left to notice.
  defp moved(socket) do
    push_event(socket, "entity-resolver:moved", %{
      id: socket.assigns.id,
      value: to_string(socket.assigns.value || ""),
      text: nil
    })
  end
end
