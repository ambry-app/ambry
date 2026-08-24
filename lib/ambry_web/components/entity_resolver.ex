defmodule AmbryWeb.Components.EntityResolver do
  @moduledoc """
  One control for "attach to an existing record, or create a new one".

  A text box with a typeahead over existing records and, when `text_name` is
  given, simultaneous new-record support: what's typed *is* the new record's
  name until an existing record is picked, and a "Create" row makes the choice
  explicit. Without `text_name` it is a pure picker for edit forms.

  Two hidden inputs carry the answer (the chosen id under `name`, the typed
  name under `text_name`), and the parent form's `phx-change` fires when they
  move, so parent LiveViews keep their existing handlers and param shapes.

  **The form is told on blur, not per keystroke.** The hidden inputs follow
  the typing, so a save posts whatever the box says; what waits for the box to
  be left is the *announcement*. That is when a native input fires `change`,
  and it is the difference between "I mean a record you don't have" and "I am
  still typing". See `moved/1`.

  The announcement comes from this component, not from watching the DOM:
  `moved/1` pushes `entity-resolver:moved` and the `entity-resolver-input`
  hook turns it into an `input` event. Watching the value attribute mutate
  cannot tell an operator's pick from the parent re-rendering this row around
  a different record.

  The list is plain markup with `phx-click` options and a keyboard hook,
  deliberately not a `<datalist>`: mobile Firefox does not support one, and it
  cannot offer a create row.

  ## Where the options come from

      search={&Books.search_books/2}   # (phrase, limit) -> [option]
      fetch={&Books.book_option/1}     #  id             -> option | nil

  The search runs per keystroke, server-side, so the context owns the query
  and can score, join and stop at a limit; filtering a preloaded list in
  memory means every form holding a picker loads every record with its cover.
  `fetch` is not decoration: without a by-id lookup a pure picker renders
  blank over a perfectly good value.

  Captured remote functions rather than an MFA tuple: checked at compile time,
  stable across renders so change tracking behaves, and greppable.

  `AmbryWeb.Components.EntityOption` owns the option shape. This component
  reads one key of it the dropdown never does, `query`, which is what the
  record is found by when that differs from how it is displayed.
  """

  use AmbryWeb, :live_component

  import AmbryWeb.Components.EntityOption

  @limit 10

  # A form control named `id` clobbers `form.id`: HTML's named getter puts
  # the control on the form object, so LiveView's patcher reads an input where
  # it expects a string and appends a second form. Refused rather than
  # documented, because the symptom points nowhere near the cause.
  @clobbers_form ~w(id name action method target elements length)

  @impl Phoenix.LiveComponent
  def render(%{name: name} = _assigns) when name in @clobbers_form do
    raise ArgumentError, """
    EntityResolver was given name=#{inspect(name)}, which clobbers the
    surrounding form's #{name} property and breaks LiveView's DOM patching.
    Qualify it ("book_id", "media_id", "person_id") and read that key in
    the parent's phx-change handler.
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:held, held(assigns))
      |> then(&assign(&1, :equery, effective_query(&1)))
      |> then(&assign(&1, :matches, matches(&1)))
      |> then(&assign(&1, :imaged, Enum.any?(&1.matches, fn option -> option.image end)))

    ~H"""
    <div
      id={@id}
      class="relative min-w-0 flex-grow"
      phx-hook="combobox-nav"
      phx-click-away={@open && JS.push("close", target: @myself)}
    >
      <%!-- One of the two carries the hook, not both: firing `input` on any
          input serializes the whole form, so a second dispatch is a second
          identical round trip. This one always exists. --%>
      <input
        type="hidden"
        id={"#{@id}-value"}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value("hidden", @value)}
        data-resolver={@id}
        phx-hook="entity-resolver-input"
      />
      <input
        :if={@text_name}
        type="hidden"
        id={"#{@id}-text"}
        name={@text_name}
        value={@text}
      />
      <input
        type="text"
        id={"#{@id}-input"}
        name={"resolver[#{@id}]"}
        value={display_value(assigns)}
        placeholder={@placeholder}
        role="combobox"
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-list"}
        aria-autocomplete="list"
        autocomplete="off"
        phx-change="filter"
        phx-focus="open"
        phx-target={@myself}
        phx-debounce="150"
        class={[@class, @text_name && "pr-20"]}
      />
      <%!-- The mode is a status, not a control: picking or typing puts you
          in the other one. Absent while the field is empty, because there is
          no outcome to name yet. --%>
      <span
        :if={@text_name && @value}
        class="bg-brand-dark/15 pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 rounded-sm px-1.5 text-xs text-lime-300"
      >
        existing
      </span>
      <span
        :if={@text_name && !@value && present?(@equery)}
        class="bg-white/10 pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 rounded-sm px-1.5 text-xs text-zinc-300"
      >
        new
      </span>
      <%!-- Flush against the box that opened it: the list is that box's
          contents spilling downward. Square on top, rounded below.

          The input keeps its own radius, since the two are not the same
          width and squaring its bottom corners would leave them visible
          either side of the seam. --%>
      <%!-- `z-[35]` is a rung on the ladder in
            `AmbryWeb.Admin.Components.layout_header/1`: clear of the sticky
            footer this may open over near the bottom of a form, under the
            scrims that mean the form is not the operator's right now. --%>
      <ul
        :if={@open}
        id={"#{@id}-list"}
        role="listbox"
        class="min-w-48 z-[35] absolute max-h-64 w-full overflow-auto rounded-b-md bg-zinc-800 text-sm shadow-xl"
      >
        <%!-- The held record is marked, not painted: being first in the list
            is most of the signal, and the input above it already wears a lime
            focus ring. A neutral lift off the list's ground and one lime
            check, the app's mark for chosen (§6). --%>
        <li
          :for={option <- @matches}
          id={"#{@id}-option-#{option.id}"}
          role="option"
          aria-selected={to_string(selected?(option, @value))}
          phx-click="pick"
          phx-value-id={option.id}
          phx-target={@myself}
          class={[
            "cursor-pointer px-3 py-2 data-[active]:bg-zinc-700 hover:bg-zinc-700",
            if(selected?(option, @value), do: "bg-white/5")
          ]}
        >
          <.option_row option={option} selected={selected?(option, @value)} imaged={@imaged} />
        </li>
        <li
          :if={@text_name && present?(@equery)}
          id={"#{@id}-option-create"}
          role="option"
          phx-click="create"
          phx-target={@myself}
          class="cursor-pointer border-t border-zinc-700 px-3 py-2 font-medium text-zinc-200 data-[active]:bg-zinc-700 hover:bg-zinc-700"
        >
          Create “{@equery}”
        </li>
        <li
          :if={@matches == [] and !(@text_name && present?(@equery))}
          class="px-3 py-2 text-zinc-500"
        >
          No matches
        </li>
      </ul>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, open: false, query: nil)}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:text_name, fn -> nil end)
     # Seeded from the field, not merely empty: a name can arrive from the
     # server, and a box rendering blank would post it away on the next
     # change.
     |> assign_new(:text, fn -> assigns[:initial_text] || "" end)
     |> assign_new(:value, fn -> nil end)
     |> then(&assign(&1, :value, held_id(&1.assigns.value)))
     |> assign_new(:placeholder, fn -> nil end)
     |> assign_new(:class, fn -> nil end)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("open", _params, socket) do
    {:noreply, assign(socket, open: true)}
  end

  # Looking away is the answer: a name typed and left alone, with nothing
  # picked, means a record the library doesn't have. The same moment a native
  # input would have fired `change`.
  def handle_event("close", _params, socket) do
    {:noreply, socket |> assign(open: false, query: nil) |> moved()}
  end

  # Typing moves the box, not the form. The hidden inputs follow every
  # keystroke, but nothing is announced until the box is left — see `moved/1`.
  def handle_event("filter", %{"resolver" => params}, socket) do
    query = params[socket.assigns.id] || ""
    socket = assign(socket, query: query, open: true)

    # With create support on, what's typed IS the new record's name until an
    # existing record is picked. A pure picker only ever changes on a pick.
    if socket.assigns.text_name,
      do: {:noreply, assign(socket, value: nil, text: query)},
      else: {:noreply, socket}
  end

  def handle_event("pick", %{"id" => id}, socket) do
    {:noreply, socket |> assign(value: id, open: false, query: nil) |> moved()}
  end

  def handle_event("create", _params, socket) do
    {:noreply,
     socket
     |> assign(value: nil, text: effective_query(socket.assigns) || "", open: false, query: nil)
     |> moved()}
  end

  # Tells the surrounding form this control moved, the way a native input
  # would: on pick, create and close, never on a keystroke.
  #
  # A keystroke is not an answer. Typing a name posts the same string as
  # meaning it, so a form told per keystroke has a half-typed author staged in
  # it from the first letter. A "the operator said Create" flag pushes that
  # job onto everything that stages a credit, which a provider chip will not
  # set.
  #
  # The three handlers below call it and nothing else does, because the DOM
  # cannot tell an operator's move from the parent re-rendering this row
  # around a different record.
  #
  # The answer travels in the event, not just the signal to go looking for it:
  # a `phx-change` already in flight locks a form's inputs, so the hook would
  # read the previous value.
  defp moved(socket) do
    push_event(socket, "entity-resolver:moved", %{
      id: socket.assigns.id,
      value: to_string(socket.assigns.value || ""),
      text: socket.assigns[:text_name] && to_string(socket.assigns.text || "")
    })
  end

  # The record this box is holding, so it can say its name. Not asked while
  # the operator is typing.
  #
  # A blank id is no id: a form posts an unpicked field as `""`, which is
  # truthy, so a freshly typed name would wear the "existing" badge.
  defp held_id(nil), do: nil
  defp held_id(""), do: nil
  defp held_id(value), do: value

  defp held(%{query: query}) when is_binary(query), do: nil
  defp held(%{value: nil}), do: nil
  defp held(%{value: value, fetch: fetch}), do: normalize(fetch.(value))

  # While typing, show the query; otherwise the held record's label, or the
  # name being created.
  defp display_value(%{query: query}) when is_binary(query), do: query
  defp display_value(%{held: %{label: label}}), do: label
  defp display_value(%{text: text}), do: text

  # What is being typed, otherwise whatever the field holds: an open filled
  # field must not list records that do not match what is in it.
  #
  # A held record answers with its own `query`, since its label may be
  # composed rather than stored.
  defp effective_query(%{query: typed}) when is_binary(typed), do: typed
  defp effective_query(%{held: %{query: term}}) when is_binary(term), do: term
  defp effective_query(assigns), do: display_value(assigns)

  # Only while the list is open: the search is a database query, and running
  # one per parent render would be a query per keystroke of every other field.
  defp matches(%{open: false}), do: []

  defp matches(%{equery: query, search: search} = assigns) do
    query
    |> search.(@limit)
    |> Enum.map(&normalize/1)
    |> pin(assigns.held)
  end

  # What the field is already holding leads the list, whether or not the
  # search surfaced it, which also stops a box saying "No matches" while
  # holding something. `held` is nil while typing, so once you type the list
  # is an answer to what you typed.
  defp pin(found, nil), do: found
  defp pin(found, held), do: [held | Enum.reject(found, &same_record?(&1, held))]

  defp same_record?(%{id: left}, %{id: right}), do: to_string(left) == to_string(right)

  defp present?(nil), do: false
  defp present?(string), do: String.trim(string) != ""
end
