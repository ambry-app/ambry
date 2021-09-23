defmodule AmbryWeb.SearchLive.AuthorResults do
  use AmbryWeb, :component

  alias Surface.Components.LiveRedirect

  prop authors, :list, required: true
end
