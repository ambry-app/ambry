defmodule Ambry.Paths do
  @moduledoc """
  Helpers for paths, like the uploads path.
  """

  @doc """
  The path on disk that uploads are saved to.
  """
  def uploads_folder_disk_path(path \\ "") do
    Path.join(Application.fetch_env!(:ambry, :uploads_path), path)
  end

  @doc """
  The path on disk where all source media folders are.
  """
  def source_media_disk_path(path \\ "") do
    Path.join([uploads_folder_disk_path(), "source_media", path])
  end

  @doc """
  The path on disk where all media files are.
  """
  def media_disk_path(path \\ "") do
    Path.join([uploads_folder_disk_path(), "media", path])
  end

  @doc """
  The path on disk where all images are.
  """
  def images_disk_path(path \\ "") do
    Path.join([uploads_folder_disk_path(), "images", path])
  end

  @doc """
  Convert a web path to a disk path.
  """
  def web_to_disk(nil), do: nil

  def web_to_disk("/uploads/" <> rest) do
    Path.join([uploads_folder_disk_path(), rest])
  end

  @doc """
  Given either a relative, web, or absolute path to an HLS master file, returns
  the equivalent HLS playlist path.
  """
  def hls_playlist_path(nil), do: nil
  def hls_playlist_path(path), do: Path.rootname(path) <> "_0.m3u8"
end
