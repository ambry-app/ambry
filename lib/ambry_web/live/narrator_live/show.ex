defmodule AmbryWeb.NarratorLive.Show do
  use AmbryWeb, :live_view

  alias Ambry.Narrators
  alias AmbryWeb.Components.BookTiles

  @impl true
  def mount(%{"id" => narrator_id}, _session, socket) do
    narrator = Narrators.get_narrator_with_books!(narrator_id)

    {:ok,
     socket
     |> assign(:page_title, narrator.name)
     |> assign(:narrator, narrator)}
  end
end
