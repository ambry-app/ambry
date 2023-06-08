defmodule Ambry.Media.Chapters do
  @moduledoc """
  Tries to determine chapters from various kinds of media.
  """

  alias Ambry.Media.Chapters.{Audnexus, ChapteredMP3, ChapteredMP4, MP4, OverdriveMP3}

  @strategies [
    Audnexus,
    ChapteredMP3,
    ChapteredMP4,
    MP4,
    OverdriveMP3
  ]

  def available_strategies(media) do
    Enum.filter(@strategies, & &1.available?(media))
  end
end
