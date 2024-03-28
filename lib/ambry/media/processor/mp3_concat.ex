defmodule Ambry.Media.Processor.MP3Concat do
  @moduledoc """
  A media processor that concatenates a collection of MP3 files and then
  converts them to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media

  @extensions ~w(.mp3)

  def name do
    "MP3 Concat"
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
