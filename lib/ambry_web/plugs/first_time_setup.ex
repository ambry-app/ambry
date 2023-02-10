defmodule AmbryWeb.Plugs.FirstTimeSetup do
  @moduledoc """
  Redirects to first-time-setup page if Ambry has not yet been set up.
  """

  @behaviour Plug

  import Phoenix.Controller, only: [redirect: 2]

  alias AmbryWeb.Router.Helpers, as: Routes

  alias Plug.Conn

  @impl Plug
  @spec init([]) :: []
  def init([]), do: []

  @impl Plug
  @spec call(Conn.t(), []) :: Conn.t()
  def call(conn, []) do
    first_time_setup? = Application.get_env(:ambry, :first_time_setup, false)
    setup_path? = match?(%Conn{path_info: ["first_time_setup" | _]}, conn)

    if first_time_setup? and not setup_path? do
      conn
      |> redirect(to: Routes.first_time_setup_setup_index_path(conn, :index))
      |> Conn.halt()
    else
      conn
    end
  end
end
