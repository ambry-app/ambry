defmodule AmbryWeb.PersonLive.Show do
  @moduledoc """
  LiveView for showing person details.
  """

  use AmbryWeb, :p_live_view

  alias Ambry.People

  @impl Phoenix.LiveView
  def mount(%{"id" => person_id}, _session, socket) do
    person = People.get_person_with_books!(person_id)

    {:ok,
     socket
     |> assign(:page_title, person.name)
     |> assign(:person, person)}
  end
end
