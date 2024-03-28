defmodule Ambry.Media.Processor.MP4 do
  @moduledoc """
  A media processor that converts a single MP4 to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "Single MP4 As-is"
  end

  def can_run?({media, filenames}) do
    can_run?(Media.files(media, @extensions) ++ filenames)
  end

  def can_run?(%Media{} = media) do
    media |> Media.files(@extensions) |> can_run?()
  end

  def can_run?(filenames) when is_list(filenames) do
    filenames |> filter_filenames(@extensions) |> length() == 1
  end

  def run(media) do
    id = copy!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp copy!(media) do
    [mp4_file] = Media.files(media, @extensions, full?: true)
    id = Media.output_id(media)

    File.cp!(
      mp4_file,
      Media.out_path(media, "#{id}.mp4")
    )

    id
  end
end
