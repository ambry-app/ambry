defmodule AmbryWeb.Components.Autocomplete do
  @moduledoc false

  use AmbryWeb, :live_component

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <input
        id={"#{@id}-value"}
        type="hidden"
        name={@name}
        value={Phoenix.HTML.Form.normalize_value("hidden", @value)}
        phx-hook="dispatch-value-change"
      />
      <input
        type="text"
        name={"autocomplete[#{@id}]"}
        value={@label}
        class={@class}
        list={@list}
        phx-change="update-value"
        phx-target={@myself}
      />
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    label =
      Enum.find_value(assigns.options, "", fn {label, value} ->
        to_string(value) == to_string(assigns[:value]) && label
      end)

    {:ok, socket |> assign(assigns) |> assign(label: label)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("update-value", %{"autocomplete" => params}, socket) do
    input = params[socket.assigns.id]

    value = Enum.find_value(socket.assigns.options, "", fn {label, value} -> label == input && value end)

    {:noreply, assign(socket, value: value)}
  end
end
