defmodule AmbryWeb.Components.EntityResolver do
  @moduledoc """
  One control for "attach to an existing record, or create a new one".

  A text box with a typeahead over existing records and — when `text_name`
  is given — simultaneous new-record support: what's typed *is* the new
  record's name until an existing record is picked, and a "Create" row in
  the list makes the choice explicit. Without `text_name` it is a pure
  picker for edit forms, where inventing records makes no sense.

  It participates in the surrounding form the way a native control would:
  two hidden inputs carry the answer (the chosen id under `name`, the typed
  name under `text_name`), and the parent form's `phx-change` fires when they
  move. Parent LiveViews keep their existing handlers and param shapes.

  **The form is told by this component, not by watching the DOM.** Every
  interaction here is handled server-side, so the hidden inputs hold the new
  answer only after the patch lands; `moved/1` pushes `entity-resolver:moved`
  and the `entity-resolver-input` hook turns it into an `input` event once it
  does. What this replaced watched the value attribute mutate instead, which
  cannot tell an operator's pick from the parent re-rendering this row around
  a different record — and reported the second one to the form as an edit.

  The list is plain markup with `phx-click` options and a small keyboard
  hook — deliberately not a `<datalist>`, which mobile Firefox does not
  support and which cannot offer a create row.

  ## Where the options come from

  Two functions, passed in:

      search={&Books.search_books/2}   # (phrase, limit) -> [option]
      fetch={&Books.book_option/1}     #  id             -> option | nil

  **The search runs per keystroke, server-side.** What this replaced took the
  whole table as a list and filtered it in memory, which meant every form
  holding a book picker loaded every book — with its cover — on mount, and the
  filtering was `String.contains?` over one label, so "sanderson kings" found
  nothing. The context owns the query instead: it can score, join, and stop at
  a limit.

  **`fetch` is not decoration.** A filled box has to name what it holds, and
  the preloaded list was answering that silently — the id was in it, so its
  label was there to find. Without a by-id lookup a pure picker renders blank
  over a perfectly good value.

  Captured remote functions rather than an MFA tuple or a source atom:
  `&Mod.fun/arity` is checked at compile time (an undefined one is a warning,
  and CI runs `--warnings-as-errors`), it is stable across renders so change
  tracking behaves, and it is greppable — the call site says which queries
  back the box.

  ## Options

  Plain `{label, id}` tuples, or maps for richer rows:

      %{id: 1, label: "A Court of Thorns and Roses", image: "/path.webp",
        detail: "GraphicAudio · 2022"}

  `image` renders a thumbnail (cover, portrait), `detail` a muted second
  line — the disambiguation lives there, so labels stay short. When any
  option in a list carries an image, imageless rows hold the space with a
  lettered placeholder so the column stays aligned. `trailer` is a muted
  aside on the label's own line, for the one fact that separates two
  same-titled records (a series and its number) when the detail line is
  already full.

  An option may also carry `query`: **what the record is found by, when that
  differs from how it is displayed.** A label composed from more than one
  column has no column to match against, so reopening a filled box searched
  for a string that could not exist and answered "No matches" about the very
  record it was holding — an audiobook in a set is labelled "A Court of
  Thorns and Roses (Part 1 of 2)" and titled "A Court of Thorns and Roses".
  The label is for reading and the query is for finding; a label that is
  itself a column needs no `query`.
  """

  use AmbryWeb, :live_component

  @limit 10

  @impl Phoenix.LiveComponent
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
          input in a form makes LiveView serialize the whole form, so a
          second dispatch is a second identical round trip. This one always
          exists; the text input is optional. --%>
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
      <%!-- The mode is a status, not a control — you can't click it into the
          other mode, picking or typing puts you there — so it wears the
          status costume: a soft-tint badge at the input's right edge, not
          the outlined prefix segment it used to be. Absent while the field
          is empty, because there is no outcome to name yet. --%>
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
      <ul
        :if={@open}
        id={"#{@id}-list"}
        role="listbox"
        class="min-w-48 absolute z-50 mt-1 max-h-64 w-full overflow-auto rounded-md bg-zinc-800 text-sm shadow-xl"
      >
        <%!-- The held record is marked, not painted. Being first in the list
            is most of the signal already, and the input two pixels above it
            is wearing a lime focus ring — a brand fill and an inset brand
            ring under that made the whole corner of the form green. So it
            takes a neutral lift off the list's own ground and one lime
            check, the app's mark for chosen (§6) at the smallest size it
            comes in. --%>
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
          <div class="flex min-w-0 items-center gap-2.5">
            <img
              :if={option.image}
              src={option.image}
              class="h-9 w-9 flex-none rounded-sm object-cover"
              loading="lazy"
              alt=""
            />
            <span
              :if={!option.image && @imaged}
              class="flex h-9 w-9 flex-none items-center justify-center rounded-sm bg-zinc-700 text-sm text-zinc-500"
            >
              {String.first(option.label)}
            </span>
            <span class="min-w-0 grow">
              <%!-- Where it sits rides the label's line, muted, rather than
                  joining a detail line already carrying five facts. No middle
                  dot: the size and colour already separate it, so the dot was
                  a second mark doing a job that was done. It gives way three
                  times faster than the title when the row runs out of width,
                  because meta truncates before content (§7). --%>
              <span class="flex min-w-0 items-baseline gap-1.5">
                <span class="min-w-0 shrink truncate">{option.label}</span>
                <span :if={option.trailer} class="shrink-[3] min-w-0 truncate text-xs text-zinc-500">
                  {option.trailer}
                </span>
              </span>
              <span :if={option.detail} class="block truncate text-xs text-zinc-400">
                {option.detail}
              </span>
            </span>
            <.icon
              :if={selected?(option, @value)}
              name="fa-check"
              class="text-brand-dark h-3.5 w-3.5 flex-none"
            />
          </div>
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
     |> assign_new(:text, fn -> "" end)
     |> assign_new(:value, fn -> nil end)
     |> assign_new(:placeholder, fn -> nil end)
     |> assign_new(:class, fn -> nil end)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("open", _params, socket) do
    {:noreply, assign(socket, open: true)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false, query: nil)}
  end

  def handle_event("filter", %{"resolver" => params}, socket) do
    query = params[socket.assigns.id] || ""
    socket = assign(socket, query: query, open: true)

    # With create support on, what's typed IS the new record's name until an
    # existing record is picked — same live behaviour the plain text input
    # had. A pure picker only ever changes on a pick.
    if socket.assigns.text_name,
      do: {:noreply, socket |> assign(value: nil, text: query) |> moved()},
      else: {:noreply, socket}
  end

  def handle_event("pick", %{"id" => id}, socket) do
    {:noreply, socket |> assign(value: id, open: false, query: nil) |> moved()}
  end

  def handle_event("create", _params, socket) do
    {:noreply,
     socket
     |> assign(
       value: nil,
       text: effective_query(socket.assigns) || "",
       open: false,
       query: nil
     )
     |> moved()}
  end

  # Tells the surrounding form that this control moved, the way a native input
  # would have.
  #
  # **Only the three handlers above call it, and that is the whole point.** The
  # hidden inputs are ordinary markup rendered from assigns, so they change
  # for two unrelated reasons: the operator picked or typed something here, or
  # the parent re-rendered this row around a different record entirely. The
  # DOM cannot tell those apart — the old hook watched the value attribute
  # mutate and fired on both, so a seeder that re-derived a credit's name had
  # its own work reported back to it as an operator edit, and the credit was
  # marked curated for something no human did.
  #
  # **The answer travels in the event, not just the signal to go looking for
  # it.** `push_event/3` is dispatched after the patch, so the hidden inputs
  # ought to hold the new answer by the time this arrives — except that a
  # `phx-change` already in flight locks a form's inputs, and typing here
  # starts one on every keystroke. Measured: typing "Alastair" and clicking
  # the match sent the form `identity_id=""` twice, because the debounced
  # filter's round trip was still open and the pick's patch could not be
  # written into the locked input. Carrying the values means the hook has
  # them whatever the DOM is allowed to say.
  defp moved(socket) do
    push_event(socket, "entity-resolver:moved", %{
      id: socket.assigns.id,
      value: to_string(socket.assigns.value || ""),
      text: socket.assigns[:text_name] && to_string(socket.assigns.text || "")
    })
  end

  # The record this box is holding, so it can say its name. Asked of the
  # source, because there is no longer a list to find it in — and not asked at
  # all while the operator is typing, which is the common case and the one
  # where the answer would be thrown away.
  defp held(%{query: query}) when is_binary(query), do: nil
  defp held(%{value: nil}), do: nil
  defp held(%{value: value, fetch: fetch}), do: normalize(fetch.(value))

  # While typing, show the query; otherwise the held record's label, or the
  # name being created.
  defp display_value(%{query: query}) when is_binary(query), do: query
  defp display_value(%{held: %{label: label}}), do: label
  defp display_value(%{text: text}), do: text

  # What the list filters on: what is being typed, otherwise whatever the
  # field currently holds — an open filled field must never list records that
  # don't match what's in it.
  #
  # A held record answers with its own `query` when it has one, because its
  # label may be composed rather than stored (see the moduledoc). Note the
  # two different `query`s in play: the assign is the operator's keystrokes,
  # `held.query` is the record's own search term.
  defp effective_query(%{query: typed}) when is_binary(typed), do: typed
  defp effective_query(%{held: %{query: term}}) when is_binary(term), do: term
  defp effective_query(assigns), do: display_value(assigns)

  # Only while the list is open. The search is a database query now, and a
  # closed box has nothing to show — running one per parent render would be a
  # query per keystroke of every other field on the form.
  defp matches(%{open: false}), do: []

  defp matches(%{equery: query, search: search} = assigns) do
    query
    |> search.(@limit)
    |> Enum.map(&normalize/1)
    |> pin(assigns.held)
  end

  # What the field is already holding leads the list.
  #
  # Opening a filled box used to drop its own record somewhere in an
  # alphabetical run of near-identical siblings — every recording of one book,
  # every narrator with the same first name — so confirming what was already
  # chosen meant reading the whole list. It is pinned whether or not the
  # search surfaced it, which also means a box can no longer say "No matches"
  # while holding something: an ordering that depends on the query is exactly
  # what made that possible.
  #
  # `held` is nil while the operator is typing, so the pin is for the opened
  # field, not for a search in progress — once you type, the list is an answer
  # to what you typed.
  defp pin(found, nil), do: found
  defp pin(found, held), do: [held | Enum.reject(found, &same_record?(&1, held))]

  defp same_record?(%{id: left}, %{id: right}), do: to_string(left) == to_string(right)

  defp normalize(nil), do: nil

  @defaults %{image: nil, detail: nil, trailer: nil, query: nil}

  defp normalize({label, id}), do: Map.merge(@defaults, %{id: id, label: label})
  defp normalize(%{id: _id, label: _label} = option), do: Map.merge(@defaults, option)

  defp selected?(_option, nil), do: false
  defp selected?(_option, ""), do: false
  defp selected?(%{id: id}, value), do: to_string(id) == to_string(value)

  defp present?(nil), do: false
  defp present?(string), do: String.trim(string) != ""
end
