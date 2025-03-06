defmodule Ambry.Utils do
  @moduledoc """
  Grab-bag of helpful utility functions
  """
  use Boundary

  alias Ambry.Utils.DeleteFiles

  require Logger

  defmacro tap_ok(tuple, fun) do
    quote bind_quoted: [fun: fun, tuple: tuple] do
      case tuple do
        {:ok, value} -> _res = fun.(value)
        _other -> :noop
      end

      tuple
    end
  end

  @doc """
  Tries to delete the given file.

  Logs output.
  """
  def try_delete_file(nil), do: :ok

  def try_delete_file(disk_path) do
    case File.rm(disk_path) do
      :ok ->
        Logger.debug(fn -> "Deleted file: #{disk_path}" end)
        :ok

      {:error, posix} ->
        Logger.warning(fn -> "Couldn't delete file (#{posix}): #{disk_path}" end)
        {:error, posix}
    end
  end

  @doc """
  Tries to delete the given files.

  Logs output.
  """
  def try_delete_files([]), do: :ok

  def try_delete_files(disk_paths) do
    for disk_path <- disk_paths do
      try_delete_file(disk_path)
    end

    :ok
  end

  @doc """
  Tries to delete the given files asynchronously.
  """
  def try_delete_files_async([]), do: {:ok, :noop}

  def try_delete_files_async(disk_paths, folder_paths \\ []) do
    %{"disk_paths" => disk_paths, "folder_paths" => folder_paths}
    |> DeleteFiles.new()
    |> Oban.insert()
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

  @doc """
  Tries to delete the given folders.

  Logs output.
  """
  def try_delete_folders([]), do: :ok

  def try_delete_folders(folder_paths) do
    for folder_path <- folder_paths do
      try_delete_folder(folder_path)
    end

    :ok
  end
end
