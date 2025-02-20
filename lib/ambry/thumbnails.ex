defmodule Ambry.Thumbnails do
  @moduledoc """
  Various sizes of thumbnails for an image and some other stuff to aide in image
  rendering.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Ambry.Paths
  alias Ambry.Thumbnails.GenerateThumbnails

  require Logger

  @primary_key false

  embedded_schema do
    field :original, :string

    field :extra_small, :string
    field :small, :string
    field :medium, :string
    field :large, :string
    field :extra_large, :string

    field :thumbhash, :string
    field :blurhash, :string
  end

  @required_fields [
    :original,
    :extra_small,
    :small,
    :medium,
    :large,
    :extra_large,
    :thumbhash
  ]

  @fields @required_fields ++ [:blurhash]

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
    thumbnails = thumbnails!(image)

    Map.merge(thumbnails, %{
      original: image_web_path,
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

  defp thumbnails!(image) do
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

    id = Ecto.UUID.generate()
    extra_small_path = write_thumbnail!(extra_small, id, "xs")
    small_path = if small, do: write_thumbnail!(small, id, "sm"), else: extra_small_path
    medium_path = if medium, do: write_thumbnail!(medium, id, "md"), else: small_path
    large_path = if large, do: write_thumbnail!(large, id, "lg"), else: medium_path

    extra_large_path =
      if extra_large, do: write_thumbnail!(extra_large, id, "xl"), else: large_path

    %{
      extra_large: Paths.disk_to_web(extra_large_path),
      large: Paths.disk_to_web(large_path),
      medium: Paths.disk_to_web(medium_path),
      small: Paths.disk_to_web(small_path),
      extra_small: Paths.disk_to_web(extra_small_path)
    }
  end

  defp write_thumbnail!(image, id, suffix) do
    filename = Path.join(Paths.images_disk_path(), "#{id}-#{suffix}.webp")
    Image.write!(image, filename, quality: 90)
    Logger.debug(fn -> "Wrote thumbnail #{filename}" end)
    filename
  end

  @doc """
  Deletes all thumbnail files for this `Thumbnails` struct.

  Ignore errors, best effort delete.
  """
  def try_delete_thumbnails(thumbnails) do
    try_delete(thumbnails.extra_large)
    try_delete(thumbnails.large)
    try_delete(thumbnails.medium)
    try_delete(thumbnails.small)
    try_delete(thumbnails.extra_small)
    :ok
  end

  defp try_delete(web_path) do
    disk_path = Paths.web_to_disk(web_path)

    case File.rm(disk_path) do
      :ok ->
        Logger.debug(fn -> "Deleted #{disk_path}" end)
        :ok

      {:error, posix} ->
        Logger.warning(fn -> "Failed to delete #{disk_path}: #{inspect(posix)}" end)
        :ok
    end
  end

  @doc """
  Schedules jobs for all media and people that have image_paths but don't have
  thumbnails.
  """
  def schedule_missing_thumbnails! do
    people =
      Ambry.Repo.all(
        from p in Ambry.People.Person,
          where: is_nil(p.thumbnails) and not is_nil(p.image_path)
      )

    Enum.each(people, fn person ->
      %{"person_id" => person.id} |> GenerateThumbnails.new() |> Oban.insert!()
    end)

    media =
      Ambry.Repo.all(
        from m in Ambry.Media.Media,
          where: is_nil(m.thumbnails) and not is_nil(m.image_path)
      )

    Enum.each(media, fn media ->
      %{"media_id" => media.id} |> GenerateThumbnails.new() |> Oban.insert!()
    end)

    :ok
  end
end
