defmodule AmbryWeb.Components.EntityResolver do
  @moduledoc """
  One control for "attach to an existing record, or create a new one".

  A text box with a typeahead over existing records and — when `text_name`
  is given — simultaneous new-record support: what's typed *is* the new
  record's name until an existing record is picked, and a "Create" row in
  the list makes the choice explicit. Without `text_name` it is a pure
  picker for edit forms, where inventing records makes no sense.

  It participates in the surrounding form the way a native control would:
  two hidden inputs (the chosen id under `name`, the typed name under
  `text_name`) fire the parent form's `phx-change` whenever they move, via
  the same dispatch-value-change hook the old autocomplete used. Parent
  LiveViews keep their existing handlers and param shapes.

  The list is plain markup with `phx-click` options and a small keyboard
  hook — deliberately not a `<datalist>`, which mobile Firefox does not
  support and which cannot offer a create row.
  """

  use AmbryWeb, :live_component

  @limit 10

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assigns
      |> assign(:equery, effective_query(assigns))
      |> then(&assign(&1, :matches, matches(&1)))

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
        phx-hook="dispatch-value-change"
      />
      <input
        :if={@text_name}
        type="hidden"
        id={"#{@id}-text"}
        name={@text_name}
        value={@text}
        phx-hook="dispatch-value-change"
      />
      <div class="flex">
        <span
          :if={@text_name}
          class="inline-flex w-20 flex-none items-center justify-center rounded-l-sm border border-r-0 border-zinc-300 bg-zinc-100 text-xs text-zinc-600 dark:border-zinc-600 dark:bg-zinc-900 dark:text-zinc-400"
        >
          {if @value, do: "Existing", else: "Create"}
        </span>
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
          class={[@class, @text_name && "rounded-l-none"]}
        />
      </div>
      <ul
        :if={@open}
        id={"#{@id}-list"}
        role="listbox"
        class="min-w-48 absolute z-50 mt-1 max-h-64 w-full overflow-auto rounded-sm border border-zinc-300 bg-white text-sm shadow-lg dark:border-zinc-600 dark:bg-zinc-800"
      >
        <li
          :for={{label, id} <- @matches}
          id={"#{@id}-option-#{id}"}
          role="option"
          aria-selected={to_string(to_string(id) == to_string(@value))}
          phx-click="pick"
          phx-value-id={id}
          phx-target={@myself}
          class="cursor-pointer px-3 py-2 data-[active]:bg-zinc-100 hover:bg-zinc-100 dark:data-[active]:bg-zinc-700 dark:hover:bg-zinc-700"
        >
          {label}
        </li>
        <li
          :if={@text_name && present?(@equery)}
          id={"#{@id}-option-create"}
          role="option"
          phx-click="create"
          phx-target={@myself}
          class="cursor-pointer border-t border-zinc-200 px-3 py-2 italic data-[active]:bg-zinc-100 hover:bg-zinc-100 dark:border-zinc-700 dark:data-[active]:bg-zinc-700 dark:hover:bg-zinc-700"
        >
          Create “{@equery}”
        </li>
        <li
          :if={@matches == [] and not (@text_name && present?(@equery))}
          class="px-3 py-2 italic text-zinc-500"
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
    socket =
      if socket.assigns.text_name,
        do: assign(socket, value: nil, text: query),
        else: socket

    {:noreply, socket}
  end

  def handle_event("pick", %{"id" => id}, socket) do
    {:noreply, assign(socket, value: id, open: false, query: nil)}
  end

  def handle_event("create", _params, socket) do
    {:noreply,
     assign(socket,
       value: nil,
       text: effective_query(socket.assigns) || "",
       open: false,
       query: nil
     )}
  end

  # While typing, show the query; otherwise the picked record's label, or the
  # name being created.
  defp display_value(%{query: query}) when is_binary(query), do: query

  defp display_value(%{value: value, options: options, text: text}) do
    case value do
      nil ->
        text

      value ->
        Enum.find_value(options, text, fn {label, id} ->
          to_string(id) == to_string(value) && label
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
    |> Enum.filter(fn {label, _id} -> String.contains?(fold(label), folded) end)
    |> Enum.sort_by(fn {label, _id} -> {!String.starts_with?(fold(label), folded), label} end)
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
