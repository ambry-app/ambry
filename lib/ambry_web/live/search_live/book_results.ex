defmodule AmbryWeb.SearchLive.BookResults do
  use AmbryWeb, :component

  alias AmbryWeb.Components.BookTiles

  prop books, :list, required: true
end
