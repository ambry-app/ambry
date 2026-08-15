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

  ## Options

  Plain `{label, id}` tuples, or maps for richer rows:

      %{id: 1, label: "A Court of Thorns and Roses", image: "/path.webp",
        detail: "GraphicAudio · 2022"}

  `image` renders a thumbnail (cover, portrait), `detail` a muted second
  line — the disambiguation lives there, so labels stay short. When any
  option in a list carries an image, imageless rows hold the space with a
  lettered placeholder so the column stays aligned.
  """

  use AmbryWeb, :live_component

  @limit 10

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assigns
      |> assign(:equery, effective_query(assigns))
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
        <li
          :for={option <- @matches}
          id={"#{@id}-option-#{option.id}"}
          role="option"
          aria-selected={to_string(to_string(option.id) == to_string(@value))}
          phx-click="pick"
          phx-value-id={option.id}
          phx-target={@myself}
          class="cursor-pointer px-3 py-2 data-[active]:bg-zinc-700 hover:bg-zinc-700"
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
            <span class="min-w-0">
              <span class="block truncate">{option.label}</span>
              <span :if={option.detail} class="block truncate text-xs text-zinc-400">
                {option.detail}
              </span>
            </span>
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
    assigns =
      case assigns do
        %{options: options} ->
          options = Enum.map(options, &normalize_option/1)
          %{assigns | options: options}

        _no_options ->
          assigns
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:text_name, fn -> nil end)
     |> assign_new(:text, fn -> "" end)
     |> assign_new(:value, fn -> nil end)
     |> assign_new(:placeholder, fn -> nil end)
     |> assign_new(:class, fn -> nil end)}
  end

  defp normalize_option({label, id}), do: %{id: id, label: label, image: nil, detail: nil}

  defp normalize_option(%{id: _, label: _} = option),
    do: Map.merge(%{image: nil, detail: nil}, option)

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

  # While typing, show the query; otherwise the picked record's label, or the
  # name being created.
  defp display_value(%{query: query}) when is_binary(query), do: query

  defp display_value(%{value: value, options: options, text: text}) do
    case value do
      nil ->
        text

      value ->
        Enum.find_value(options, text, fn option ->
          to_string(option.id) == to_string(value) && option.label
        end)
    end
  end

  # What the list filters on: the query while typing, otherwise whatever the
  # field currently holds — an open filled field must never list records that
  # don't match what's in it.
  defp effective_query(%{query: query}) when is_binary(query), do: query
  defp effective_query(assigns), do: display_value(assigns)

  defp matches(%{equery: query, options: options}) when is_binary(query) and query != "" do
    folded = fold(query)

    options
    |> Enum.filter(fn option -> String.contains?(fold(option.label), folded) end)
    |> Enum.sort_by(fn option ->
      {!String.starts_with?(fold(option.label), folded), option.label}
    end)
    |> Enum.take(@limit)
  end

  defp matches(%{options: options}), do: Enum.take(options, @limit)

  # Case- and accent-insensitive: "Rodriguez" finds "Patricia Rodríguez".
  defp fold(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  defp present?(nil), do: false
  defp present?(string), do: String.trim(string) != ""
end
