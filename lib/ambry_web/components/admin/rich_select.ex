defmodule AmbryWeb.Admin.Components.RichSelect do
  @moduledoc false
  use AmbryWeb, :live_component

  attr :id, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :options, :list, required: true
  attr :option_value, :any, default: &__MODULE__.default_option_value/1
  attr :prompt, :string, default: "​"

  slot :option, required: true

  def rich_select(assigns) do
    ~H"""
    <.live_component
      id={@id}
      module={__MODULE__}
      field={@field}
      options={@options}
      option_value={@option_value}
      option={@option}
      prompt={@prompt}
    />
    """
  end

  def default_option_value(option), do: option.id

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    selected_option =
      Enum.find(assigns.options, fn option ->
        to_string(assigns.option_value.(option)) == to_string(assigns.field.value)
      end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       selected_option: selected_option,
       open: false
     )}
  end

  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, open: !socket.assigns.open)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def render(assigns) do
    ~H"""
    <div class="cursor-pointer" phx-click-away="close" phx-target={@myself}>
      <div
        class="py-[7px] px-[11px] flex items-center rounded-sm border border-zinc-600 bg-zinc-800 text-zinc-300"
        phx-click="toggle"
        phx-target={@myself}
      >
        <div class="grow">
          <%= if @selected_option do %>
            <%= render_slot(@option, @selected_option) %>
          <% else %>
            <span class="text-zinc-500"><%= @prompt %></span>
          <% end %>
        </div>
        <FA.icon name="angle-down" class="h-4 w-4 flex-none fill-zinc-500" />
      </div>

      <div class="relative w-full">
        <div class={[
          "absolute top-0 right-0 left-0 max-h-96 overflow-y-auto rounded-sm border border-t-0 border-zinc-600 bg-zinc-950 shadow-lg",
          if(!@open, do: "hidden")
        ]}>
          <div
            :for={option <- @options}
            class={["relative hover:bg-zinc-900", if(option == @selected_option, do: "bg-zinc-900")]}
          >
            <label class="absolute inset-0 cursor-pointer">
              <.radio_input field={@field} value={@option_value.(option)} />
            </label>
            <div class="py-[7px] px-[11px]">
              <%= render_slot(@option, option) %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Components

  attr :field, Phoenix.HTML.FormField, required: true
  attr :value, :any, required: true

  defp radio_input(assigns) do
    assigns = assign(assigns, :checked, to_string(assigns.value) == to_string(assigns.field.value))

    ~H"""
    <input id={"#{@field.id}-#{@value}"} type="radio" class="hidden" value={@value} name={@field.name} checked={@checked} />
    """
  end
end
