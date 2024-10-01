defmodule Ambry.Thumbnails do
  @moduledoc """
  Various sizes of thumbnails for an image and some other stuff to aide in image
  rendering.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Paths

  @primary_key false

  embedded_schema do
    field :extra_small, :string
    field :small, :string
    field :medium, :string
    field :large, :string
    field :extra_large, :string

    field :thumbhash, :string
    field :blurhash, :string
  end

  @fields [
    :extra_small,
    :small,
    :medium,
    :large,
    :extra_large,
    :thumbhash,
    :blurhash
  ]

  @required_fields [
    :extra_small,
    :small,
    :medium,
    :large,
    :extra_large,
    :thumbhash
  ]

  def changeset(thumbnails, attrs) do
    thumbnails
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
  end

  def generate_thumbnails!(image_web_path) do
    disk_path = Paths.web_to_disk(image_web_path)
    image = Image.open!(disk_path)

    thumbhash = thumbhash!(image)
    blurhash = blurhash!(image)
    thumbnails = thumbnails!(image, disk_path)

    Map.merge(thumbnails, %{
      thumbhash: thumbhash,
      blurhash: blurhash
    })
  end

  defp thumbhash!(image) do
    rgba = image_to_rgba(image)
    bin = Thumbhash.rgba_to_thumb_hash(75, 100, :array.from_list(rgba))
    Base.encode64(bin)
  end

  defp image_to_rgba(image) do
    if Image.has_alpha?(image) do
      {:ok, data} = Vix.Vips.Image.write_to_binary(image)
      :binary.bin_to_list(data)
    else
      image = Image.add_alpha!(image, 255)

      {:ok, data} = Vix.Vips.Image.write_to_binary(image)
      :binary.bin_to_list(data)
    end
  end

  defp blurhash!(image) do
    case Image.Blurhash.encode(image) do
      {:ok, blurhash} -> blurhash
      _ -> nil
    end
  end

  defp thumbnails!(image, disk_path) do
    {width, height, _bands} = Image.shape(image)
    length = min(width, height)

    {extra_large, large, medium, small, extra_small} =
      cond do
        length > 1024 ->
          extra_large = Image.thumbnail!(image, "1024x1024", crop: :high, fit: :cover)

          {
            extra_large,
            Image.thumbnail!(extra_large, "512x512"),
            Image.thumbnail!(extra_large, "256x256"),
            Image.thumbnail!(extra_large, "128x128"),
            Image.thumbnail!(extra_large, "64x64")
          }

        length > 512 ->
          extra_large = Image.thumbnail!(image, "#{length}x#{length}", crop: :high, fit: :cover)

          {
            extra_large,
            Image.thumbnail!(extra_large, "512x512"),
            Image.thumbnail!(extra_large, "256x256"),
            Image.thumbnail!(extra_large, "128x128"),
            Image.thumbnail!(extra_large, "64x64")
          }

        length > 256 ->
          extra_large = Image.thumbnail!(image, "#{length}x#{length}", crop: :high, fit: :cover)

          {
            nil,
            extra_large,
            Image.thumbnail!(extra_large, "256x256"),
            Image.thumbnail!(extra_large, "128x128"),
            Image.thumbnail!(extra_large, "64x64")
          }

        length > 128 ->
          extra_large = Image.thumbnail!(image, "#{length}x#{length}", crop: :high, fit: :cover)

          {
            nil,
            nil,
            extra_large,
            Image.thumbnail!(extra_large, "128x128"),
            Image.thumbnail!(extra_large, "64x64")
          }

        length > 64 ->
          extra_large = Image.thumbnail!(image, "#{length}x#{length}", crop: :high, fit: :cover)

          {
            nil,
            nil,
            nil,
            extra_large,
            Image.thumbnail!(extra_large, "64x64")
          }

        true ->
          extra_large = Image.thumbnail!(image, "#{length}x#{length}", crop: :high, fit: :cover)

          {
            nil,
            nil,
            nil,
            nil,
            extra_large
          }
      end

    extra_small_path = write_thumbnail!(extra_small, disk_path, "xs")
    small_path = if small, do: write_thumbnail!(small, disk_path, "sm"), else: extra_small_path
    medium_path = if medium, do: write_thumbnail!(medium, disk_path, "md"), else: small_path
    large_path = if large, do: write_thumbnail!(large, disk_path, "lg"), else: medium_path

    extra_large_path =
      if extra_large, do: write_thumbnail!(extra_large, disk_path, "xl"), else: large_path

    %{
      extra_large: Paths.disk_to_web(extra_large_path),
      large: Paths.disk_to_web(large_path),
      medium: Paths.disk_to_web(medium_path),
      small: Paths.disk_to_web(small_path),
      extra_small: Paths.disk_to_web(extra_small_path)
    }
  end

  defp write_thumbnail!(image, disk_path, suffix) do
    filename = Path.rootname(disk_path) <> "-" <> suffix <> ".webp"
    Image.write!(image, filename, quality: 85)
    filename
  end

  @doc """
  Deletes all thumbnail files for this `Thumbnails` struct.

  Ignore errors, best effort delete.
  """
  def try_delete_thumbnails(thumbnails) do
    File.rm(Paths.web_to_disk(thumbnails.extra_large))
    File.rm(Paths.web_to_disk(thumbnails.large))
    File.rm(Paths.web_to_disk(thumbnails.medium))
    File.rm(Paths.web_to_disk(thumbnails.small))
    File.rm(Paths.web_to_disk(thumbnails.extra_small))
    :ok
  end
end
