defmodule AmbryWeb.SearchLive.SeriesResults do
  @moduledoc false

  use AmbryWeb, :live_component

  alias AmbryWeb.Components.SeriesTiles

  prop series, :list, required: true
end
