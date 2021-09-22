defmodule AmbryWeb.HeaderLive.PlayButton do
  use AmbryWeb, :component

  prop playing, :boolean, required: true
  prop click, :event, required: true
end
