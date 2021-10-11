defmodule AmbryWeb.API.SeriesView do
  use AmbryWeb, :view

  alias AmbryWeb.API.{BookView, SeriesView}

  def render("show.json", %{series: series}) do
    %{data: render_one(series, SeriesView, "series.json")}
  end

  def render("series.json", %{series: series}) do
    %{
      id: series.id,
      name: series.name,
      books: render_many(series.series_books, BookView, "book_index.json")
    }
  end
end
