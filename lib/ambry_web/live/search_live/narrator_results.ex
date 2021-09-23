defmodule AmbryWeb.SearchLive.NarratorResults do
  use AmbryWeb, :component

  alias Surface.Components.LiveRedirect

  prop narrators, :list, required: true
end
