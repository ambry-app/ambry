defmodule AmbryWeb.PersonLive.Show do
  @moduledoc """
  LiveView for showing person details.
  """

  use AmbryWeb, :p_live_view

  import AmbryWeb.Components

  alias Ambry.People

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl Phoenix.LiveView
  def mount(%{"id" => person_id}, _session, socket) do
    person = People.get_person_with_books!(person_id)

    {:ok,
     socket
     |> assign(:page_title, person.name)
     |> assign(:person, person)}
  end
end
