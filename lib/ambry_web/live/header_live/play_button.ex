defmodule AmbryWeb.HeaderLive.PlayButton do
  @moduledoc false

  use AmbryWeb, :component

  prop playing, :boolean, required: true
  prop click, :event, required: true
end
