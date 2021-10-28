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
    mp4_file = media.mp4_path |> Paths.web_to_disk() |> file_stat() |> unwrap()
    mpd_file = media.mpd_path |> Paths.web_to_disk() |> file_stat() |> unwrap()
    hls_master = media.hls_path |> Paths.web_to_disk() |> file_stat() |> unwrap()
    hls_playlist = media |> hls_playlist_path() |> Paths.web_to_disk() |> file_stat() |> unwrap()

    %{
      source_files: source_files,
      mp4_file: mp4_file,
      mpd_file: mpd_file,
      hls_master: hls_master,
      hls_playlist: hls_playlist
    }
  end

  defp unwrap(nil), do: nil
  defp unwrap([single]), do: single

  defp source_file_stats(media) do
    case File.ls(media.source_path) do
      {:ok, relative_paths} ->
        relative_paths
        |> NaturalSort.sort()
        |> Enum.flat_map(fn path ->
          file_stat(Path.join([media.source_path, path]))
        end)

      {:error, posix} ->
        posix
    end
  end

  defp file_stat(nil), do: nil

  defp file_stat(path) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, relative_paths} ->
          relative_paths
          |> NaturalSort.sort()
          |> Enum.flat_map(fn p ->
            file_stat(Path.join([path, p]))
          end)

        {:error, posix} ->
          [%{path: path, stat: posix}]
      end
    else
      case File.stat(path) do
        {:ok, stat} -> [%{path: path, stat: stat}]
        {:error, posix} -> [%{path: path, stat: posix}]
      end
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
      |> MapSet.new()

    existing_files = Paths.media_disk_path() |> File.ls!() |> MapSet.new()

    query =
      from m in Media,
        select: %{
          id: m.id,
          source_folder: fragment("regexp_replace(source_path, '^.*/', '')"),
          mpd_file: fragment("regexp_replace(mpd_path, '^.*/', '')"),
          hls_file: fragment("regexp_replace(hls_path, '^.*/', '')"),
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
        id: Ecto.UUID.generate(),
        path: full_path,
        size: folder_size(full_path)
      }
    end)
  end

  # files with no references
  defp orphaned_media_files(media, existing_files) do
    referenced_files = media |> Enum.flat_map(&referenced_files/1) |> MapSet.new()
    orphaned_files = MapSet.difference(existing_files, referenced_files)

    Enum.map(orphaned_files, fn file ->
      full_path = Paths.media_disk_path(file)

      %{
        id: Ecto.UUID.generate(),
        path: full_path,
        size: FileSize.from_file!(full_path)
      }
    end)
  end

  defp referenced_files(media) do
    Enum.filter(
      [
        media.mp4_file,
        media.mpd_file,
        media.hls_file,
        hls_playlist_file(media)
      ],
      & &1
    )
  end

  defp broken_media(media, existing_folders, existing_files) do
    broken_media =
      Enum.flat_map(media, fn media ->
        source? = MapSet.member?(existing_folders, media.source_folder)
        mp4? = MapSet.member?(existing_files, media.mp4_file)
        mpd? = MapSet.member?(existing_files, media.mpd_file)
        hls_master? = MapSet.member?(existing_files, media.hls_file)
        hls_playlist? = MapSet.member?(existing_files, hls_playlist_file(media))

        if source? && mp4? && mpd? && hls_master? && hls_playlist? do
          []
        else
          [
            %{
              id: media.id,
              source?: source?,
              mp4?: mp4?,
              mpd?: mpd?,
              hls_master?: hls_master?,
              hls_playlist?: hls_playlist?
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
        mp4?: broken_media.mp4?,
        mpd?: broken_media.mpd?,
        hls_master?: broken_media.hls_master?,
        hls_playlist?: broken_media.hls_playlist?
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

  # A %Media{} struct from ecto
  defp hls_playlist_path(%Media{hls_path: hls_path}) do
    Paths.hls_playlist_path(hls_path)
  end

  # A plain map from custom query
  defp hls_playlist_file(%{hls_file: hls_file}) do
    Paths.hls_playlist_path(hls_file)
  end
end
