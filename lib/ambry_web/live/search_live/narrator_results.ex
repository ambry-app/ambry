defmodule AmbryWeb.SearchLive.NarratorResults do
  @moduledoc false

  use AmbryWeb, :component

  alias AmbryWeb.Endpoint

  alias Surface.Components.LiveRedirect

  prop narrators, :list, required: true
end
