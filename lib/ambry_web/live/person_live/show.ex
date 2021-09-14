defmodule AmbryWeb.PersonLive.Show do
  use AmbryWeb, :live_view

  alias Ambry.People
  alias AmbryWeb.Components.BookTiles

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl true
  def mount(%{"id" => person_id}, _session, socket) do
    person = People.get_person_with_books!(person_id)

    {:ok,
     socket
     |> assign(:page_title, person.name)
     |> assign(:person, person)}
  end
end
