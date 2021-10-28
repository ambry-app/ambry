defmodule AmbryWeb.SearchLive.AuthorResults do
  @moduledoc false

  use AmbryWeb, :component

  alias AmbryWeb.Endpoint

  alias Surface.Components.LiveRedirect

  prop authors, :list, required: true
end
