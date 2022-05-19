defmodule AmbryWeb.API.SeriesController do
  use AmbryWeb, :controller

  alias Ambry.Series

  def show(conn, %{"id" => id}) do
    series = Series.get_series_with_books!(id)
    render(conn, "show.json", series: series)
  end
end
