defmodule AmbryWeb.SearchLive.AuthorResults do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Surface.Components.LiveRedirect

  prop authors, :list, required: true
end
