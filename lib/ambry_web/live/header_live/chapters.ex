defmodule AmbryWeb.HeaderLive.Chapters do
  @moduledoc false

  use AmbryWeb, :component

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  prop dismiss, :event, required: true
  prop chapters, :list, required: true
end
