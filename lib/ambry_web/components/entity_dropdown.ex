defmodule AmbryWeb.Components.EntityDropdown do
  @moduledoc """
  The plain drop-down: click it, see what there is, click one.

  A typeahead is the wrong control when the answer is one of three. The
  twin of `AmbryWeb.Components.EntityResolver` to look at (both draw
  `AmbryWeb.Components.EntityOption.option_row/1`), but there is nothing to
  type and nothing to search: the options arrive with the component, in
  reading order.

      options={[%{id: 1, label: "The Expanse", image: "/x.webp", detail: "2 of 3 parts"}]}
      value={@form[:recording_group_id].value}

  A native `<select>` cannot render a cover and a second line, and its menu
  is drawn by the OS, so two pickers on one form would not match.

  Same contract as the resolver: a hidden input carries the answer, every
  interaction is handled server-side, and `moved/1` pushes
  `entity-resolver:moved` for the `entity-resolver-input` hook.
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
      <%!-- A button, not a styled div: one tab stop, opens on Enter and
          Space for free, and wears the `role=combobox` `combobox-nav` looks
          for. --%>
      <button
        type="button"
        id={"#{@id}-trigger"}
        role="combobox"
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-list"}
        phx-click={JS.push("toggle", target: @myself)}
        class={[@class, "flex items-center gap-2 pr-8 text-left"]}
      >
        <%!-- A non-breaking space, not "": an empty inline span has no line
            box, and this reserves exactly what text would at any
            breakpoint. --%>
        <span class="min-w-0 truncate">
          {(@held && @held.label) || "\u00A0"}
        </span>
        <.icon
          name="fa-chevron-down"
          class="absolute top-1/2 right-3 h-3 w-3 -translate-y-1/2 text-zinc-500"
        />
      </button>
      <%!-- `z-[35]` on the ladder in
          `AmbryWeb.Admin.Components.layout_header/1`; matched to the
          resolver's list on purpose. --%>
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

  # Same signal and hook as the resolver's: the form is told, not left to
  # notice.
  defp moved(socket) do
    push_event(socket, "entity-resolver:moved", %{
      id: socket.assigns.id,
      value: to_string(socket.assigns.value || ""),
      text: nil
    })
  end
end
