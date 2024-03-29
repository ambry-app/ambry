defmodule Ambry.FileUtils do
  @moduledoc """
  Utility functions for managing files on disk.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Paths
  alias Ambry.People.Person
  alias Ambry.Repo

  require Logger

  @doc """
  Checks the given image web_path to see if it's used by any other books or
  people, and if not, attempts to delete it from disk.
  """
  def maybe_delete_image(nil), do: :noop

  def maybe_delete_image(web_path) do
    book_count = Repo.aggregate(from(b in Book, where: b.image_path == ^web_path), :count)
    person_count = Repo.aggregate(from(p in Person, where: p.image_path == ^web_path), :count)

    if book_count + person_count == 0 do
      disk_path = Paths.web_to_disk(web_path)

      try_delete_file(disk_path)
    else
      Logger.warning(fn -> "Not deleting file because it's still in use: #{web_path}" end)
      {:error, :still_in_use}
    end
  end

  @doc """
  Tries to delete all existing media files for a given media.
  """
  def delete_media_files(media) do
    %{
      source_path: source_disk_path,
      mpd_path: mpd_path,
      hls_path: hls_path,
      mp4_path: mp4_path
    } = media

    try_delete_folder(source_disk_path)

    mpd_path |> Paths.web_to_disk() |> try_delete_file()
    hls_path |> Paths.web_to_disk() |> try_delete_file()
    mp4_path |> Paths.web_to_disk() |> try_delete_file()
    hls_path |> Paths.hls_playlist_path() |> Paths.web_to_disk() |> try_delete_file()

    :ok
  end

  @doc """
  Tries to delete the given file.

  Logs output.
  """
  def try_delete_file(nil), do: :noop

  def try_delete_file(disk_path) do
    case File.rm(disk_path) do
      :ok ->
        Logger.info(fn -> "Deleted file: #{disk_path}" end)
        :ok

      {:error, posix} ->
        Logger.warning(fn -> "Couldn't delete file (#{posix}): #{disk_path}" end)
        {:error, posix}
    end
  end

  @doc """
  Tries to delete the given folder.

  Logs output.
  """
  def try_delete_folder(nil), do: :noop

  def try_delete_folder(disk_path) do
    case File.rm_rf(disk_path) do
      {:ok, paths} ->
        for path <- paths, do: Logger.info(fn -> "Deleted file/folder: #{path}" end)

        :ok

      {:error, posix, path} ->
        # coveralls-ignore-start
        Logger.warning(fn -> "Couldn't delete file/folder (#{posix}): #{path}" end)
        {:error, posix, path}
        # coveralls-ignore-stop
    end
  end
end
