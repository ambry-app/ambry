defmodule AmbryWeb.BookLive.Header do
  @moduledoc false

  use AmbryWeb, :component

  alias AmbryWeb.Endpoint

  alias Surface.Components.LiveRedirect

  prop book, :any
end
