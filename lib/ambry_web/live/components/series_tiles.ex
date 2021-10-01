defmodule AmbryWeb.Components.SeriesTiles do
  @moduledoc """
  Renders a responsive tiled grid of series links.
  """

  use AmbryWeb, :component

  alias Surface.Components.LiveRedirect

  prop series, :list
end
