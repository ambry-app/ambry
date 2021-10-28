defmodule AmbryWeb.SearchLive.BookResults do
  @moduledoc false

  use AmbryWeb, :live_component

  alias AmbryWeb.Components.BookTiles

  prop books, :list, required: true
end
