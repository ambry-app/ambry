defmodule AmbryWeb.BookLive.Header do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Surface.Components.LiveRedirect

  prop book, :any
end
