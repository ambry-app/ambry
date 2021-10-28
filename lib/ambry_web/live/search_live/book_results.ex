defmodule AmbryWeb.SearchLive.BookResults do
  @moduledoc false

  use AmbryWeb, :component

  alias AmbryWeb.Components.BookTiles

  prop books, :list, required: true
end
