defmodule AmbryWeb.PageController do
  use AmbryWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
