defmodule Ambry.Media.Processor.MP4ConcatReEncode do
  @moduledoc """
  A media processor that concatenates a collection of MP4 files, re-encodes
  them, and then converts them to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "MP4 Concat Re-encode"
  end

  def can_run?({media, filenames}) do
    can_run?(Media.files(media, @extensions, full?: true) ++ filenames)
  end

  def can_run?(%Media{} = media) do
    media |> Media.files(@extensions, full?: true) |> can_run?()
  end

  def can_run?(filenames) when is_list(filenames) do
    filenames |> filter_filenames(@extensions) |> length() > 1
  end

  def run(media) do
    id = concat_files!(media, @extensions)
    create_stream!(media, id)
    finalize!(media, id)
  end
end
