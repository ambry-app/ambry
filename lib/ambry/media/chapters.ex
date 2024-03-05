defmodule Ambry.Media.Chapters do
  @moduledoc """
  Tries to determine chapters from various kinds of media.
  """

  alias Ambry.Media.Chapters.ChapteredMP3
  alias Ambry.Media.Chapters.ChapteredMP4
  alias Ambry.Media.Chapters.MP4

  @strategies [
    ChapteredMP3,
    ChapteredMP4,
    MP4
  ]

  def available_strategies(media) do
    Enum.filter(@strategies, & &1.available?(media))
  end
end
