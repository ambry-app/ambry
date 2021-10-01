defmodule AmbryWeb.Components.Modal do
  @moduledoc """
  Modal component with close button and return_to url.
  """

  use AmbryWeb, :live_component

  alias Surface.Components.LivePatch

  prop return_to, :string, required: true

  slot default, required: true

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.return_to)}
  end
end
