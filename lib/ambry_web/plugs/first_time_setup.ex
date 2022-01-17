defmodule AmbryWeb.Plugs.FirstTimeSetup do
  @moduledoc """
  Redirects to first-time-setup page if Ambry has not yet been set up.
  """

  @behaviour Plug

  import Phoenix.Controller, only: [redirect: 2]

  alias AmbryWeb.Router.Helpers, as: Routes

  alias Plug.Conn

  @impl Plug
  @spec init([]) :: boolean()
  def init([]) do
    Application.get_env(:ambry, :first_time_setup, false)
  end

  @impl Plug
  @spec call(Conn.t(), boolean) :: Conn.t()
  def call(conn, false), do: conn

  def call(%Conn{path_info: ["first_time_setup" | _]} = conn, true), do: conn

  def call(conn, true) do
    conn
    |> redirect(to: Routes.first_time_setup_setup_index_path(conn, :index))
    |> Conn.halt()
  end
end
