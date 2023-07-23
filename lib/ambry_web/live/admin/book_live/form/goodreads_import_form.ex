defmodule AmbryWeb.Admin.BookLive.Form.GoodreadsImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end
end
