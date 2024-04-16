defmodule Ambry.Utils do
  @moduledoc """
  Grab-bag of helpful utility functions
  """

  use Boundary

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
