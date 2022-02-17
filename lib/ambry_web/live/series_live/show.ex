defmodule AmbryWeb.SeriesLive.Show do
  @moduledoc """
  LiveView for showing all books in a series.
  """

  use AmbryWeb, :p_live_view

  alias Ambry.Series

  @impl Phoenix.LiveView
  def mount(%{"id" => series_id}, _session, socket) do
    series = Series.get_series_with_books!(series_id)

    authors =
      series.series_books
      |> Enum.flat_map(& &1.book.authors)
      |> Enum.uniq()

    {:ok,
     socket
     |> assign(:page_title, series.name)
     |> assign(:series, series)
     |> assign(:authors, authors)}
  end
end
