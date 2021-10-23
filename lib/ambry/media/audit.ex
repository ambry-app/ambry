defmodule Ambry.Media.Audit do
  @moduledoc """
  Functions to audit media files on disk.
  """

  import Ecto.Query

  alias Ambry.Media.Media
  alias Ambry.{Paths, Repo}

  @doc """
  Get details about the files on disk related to the given media.
  """
  def get_media_file_details(media) do
    source_files = source_file_stats(media)
    mp4_file = media.mp4_path |> Paths.web_to_disk() |> file_stat()
    mpd_file = media.mpd_path |> Paths.web_to_disk() |> file_stat()

    %{
      source_files: source_files,
      mp4_file: mp4_file,
      mpd_file: mpd_file
    }
  end

  defp source_file_stats(media) do
    case File.ls(media.source_path) do
      {:ok, relative_paths} ->
        relative_paths
        |> NaturalSort.sort()
        |> Enum.map(fn path ->
          file_stat(Path.join([media.source_path, path]))
        end)

      {:error, posix} ->
        posix
    end
  end

  defp file_stat(path) do
    case File.stat(path) do
      {:ok, stat} -> %{path: path, stat: stat}
      {:error, posix} -> %{path: path, stat: posix}
    end
  end

  @doc """
  Audit the filesystem to see if there are any large media files not referenced
  by any media objects.

  Also returns a list of all broken media (referencing missing files or
  folders).
  """
  def orphaned_files_audit do
    existing_folders =
      Paths.source_media_disk_path()
      |> File.ls!()
      |> Enum.reject(fn folder ->
        folder |> Paths.source_media_disk_path() |> File.ls!() == []
      end)
      |> MapSet.new()

    existing_files = Paths.media_disk_path() |> File.ls!() |> MapSet.new()

    query =
      from m in Media,
        select: %{
          id: m.id,
          source_folder: fragment("regexp_replace(source_path, '^.*/', '')"),
          mpd_file: fragment("regexp_replace(mpd_path, '^.*/', '')"),
          mp4_file: fragment("regexp_replace(mp4_path, '^.*/', '')")
        }

    media = Repo.all(query)

    %{
      orphaned_source_folders: orphaned_source_folders(media, existing_folders),
      orphaned_media_files: orphaned_media_files(media, existing_files),
      broken_media: broken_media(media, existing_folders, existing_files)
    }
  end

  # source folders with no references
  defp orphaned_source_folders(media, existing_folders) do
    referenced_folders = MapSet.new(media, &Map.get(&1, :source_folder))
    orphaned_folders = MapSet.difference(existing_folders, referenced_folders)

    Enum.map(orphaned_folders, fn folder ->
      full_path = Paths.source_media_disk_path(folder)

      %{
        path: full_path,
        size: folder_size(full_path)
      }
    end)
  end

  # files with no references
  defp orphaned_media_files(media, existing_files) do
    referenced_files = media |> Enum.flat_map(&[&1.mpd_file, &1.mp4_file]) |> MapSet.new()
    orphaned_files = MapSet.difference(existing_files, referenced_files)

    Enum.map(orphaned_files, fn file ->
      full_path = Paths.media_disk_path(file)

      %{
        path: full_path,
        size: FileSize.from_file!(full_path)
      }
    end)
  end

  defp broken_media(media, existing_folders, existing_files) do
    broken_media =
      Enum.flat_map(media, fn media ->
        source? = MapSet.member?(existing_folders, media.source_folder)
        mpd? = MapSet.member?(existing_files, media.mpd_file)
        mp4? = MapSet.member?(existing_files, media.mp4_file)

        if source? && mpd? && mp4? do
          []
        else
          [
            %{
              id: media.id,
              source?: source?,
              mpd?: mpd?,
              mp4?: mp4?
            }
          ]
        end
      end)

    broken_media_ids = Enum.map(broken_media, & &1.id)

    query =
      from m in Media,
        preload: [:book, media_narrators: [:narrator]],
        where: m.id in ^broken_media_ids

    broken_media_structs_by_id = query |> Repo.all() |> Map.new(&{&1.id, &1})

    Enum.map(broken_media, fn broken_media ->
      %{
        media: Map.fetch!(broken_media_structs_by_id, broken_media.id),
        source?: broken_media.source?,
        mpd?: broken_media.mpd?,
        mp4?: broken_media.mp4?
      }
    end)
  end

  defp folder_size(folder_path) do
    folder_path
    |> File.ls!()
    |> Enum.map(fn file_path ->
      full_path = Path.join([folder_path, file_path])
      FileSize.from_file!(full_path)
    end)
    |> Enum.reduce(FileSize.from_bytes(0), fn size, acc ->
      FileSize.add(size, acc)
    end)
  end
end
