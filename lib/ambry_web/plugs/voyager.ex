defmodule AmbryWeb.Plugs.Voyager do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn
  alias Plug.Conn

  @voyager_html_path Path.join(:code.priv_dir(:ambry), "static/voyager.html")
  @external_resource @voyager_html_path
  @voyager_html File.read!(@voyager_html_path)

  @impl Plug
  @spec init([]) :: []
  def init([]), do: []

  @impl Plug
  @spec call(Conn.t(), []) :: Conn.t()
  def call(conn, []) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, @voyager_html)
  end
end
