defmodule AmbryWeb.Components.Modal do
  @moduledoc """
  Modal component with close button and return_to url.
  """

  use AmbryWeb, :live_component

  @impl Phoenix.LiveComponent
  def handle_event("close", _params, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.return_to)}
  end
end
