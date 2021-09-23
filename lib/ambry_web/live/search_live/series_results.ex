defmodule AmbryWeb.SearchLive.SeriesResults do
  use AmbryWeb, :component

  alias AmbryWeb.Components.SeriesTiles

  prop series, :list, required: true
end
