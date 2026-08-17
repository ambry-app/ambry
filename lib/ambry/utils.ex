defmodule Ambry.Utils do
  @moduledoc """
  Grab-bag of helpful utility functions
  """
  use Boundary

  alias Ambry.Utils.DeleteFiles

  require Logger

  @byte_units ["B", "kB", "MB", "GB", "TB", "PB"]

  @doc """
  Descriptive User-Agent for outbound HTTP requests.

  Some services (notably the Wikimedia family) throttle or block generic
  library UAs; their API etiquette asks for an identifying agent with a
  contact point.
  """
  @spec http_user_agent() :: String.t()
  def http_user_agent do
    "Ambry/#{Application.spec(:ambry, :vsn)} (https://github.com/ambry-app/ambry)"
  end

  @doc """
  Formats a byte count as a human-readable string using SI (1000-based) units,
  rounded to a whole number.

  ## Examples

      iex> Ambry.Utils.humanize_bytes(0)
      "0 B"

      iex> Ambry.Utils.humanize_bytes(1500)
      "2 kB"

      iex> Ambry.Utils.humanize_bytes(1_073_741_824)
      "1 GB"
  """
  @spec humanize_bytes(non_neg_integer()) :: String.t()
  def humanize_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    humanize_bytes(bytes / 1, @byte_units)
  end

  defp humanize_bytes(value, [unit]), do: "#{round(value)} #{unit}"

  defp humanize_bytes(value, [unit | larger_units]) do
    if value >= 1000 do
      humanize_bytes(value / 1000, larger_units)
    else
      "#{round(value)} #{unit}"
    end
  end

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

  def try_delete_files_async(disk_paths, folder_paths \\ [], opts \\ []) do
    %{"disk_paths" => disk_paths, "folder_paths" => folder_paths}
    |> maybe_put("prune_until", opts[:prune_until])
    |> maybe_put("prune_from", opts[:prune_from])
    |> DeleteFiles.new()
    |> Oban.insert()
  end

  defp maybe_put(args, _key, nil), do: args
  defp maybe_put(args, key, value), do: Map.put(args, key, value)

  @doc """
  Removes now-empty parent folders, walking up from each given folder.

  Deleting the last book by an author leaves `Brandon Sanderson/The
  Stormlight Archive/` standing empty, and a library tree that only ever
  accumulates empty folders isn't organized for long.

  Stops at the first folder that still holds something, and never removes one
  of `stop_paths` — those are the registered library roots, whose existence
  is configuration rather than a side effect of holding a book.
  """
  def try_prune_empty_parents(folder_paths, stop_paths) do
    stop = MapSet.new(stop_paths)

    for folder_path <- folder_paths, is_binary(folder_path) do
      prune_empty_parents(Path.dirname(folder_path), stop)
    end

    :ok
  end

  defp prune_empty_parents(path, stop) do
    parent = Path.dirname(path)

    cond do
      MapSet.member?(stop, path) -> :ok
      parent == path -> :ok
      not empty_dir?(path) -> :ok
      File.rmdir(path) != :ok -> :ok
      true -> prune_empty_parents(parent, stop)
    end
  end

  defp empty_dir?(path) do
    match?({:ok, []}, File.ls(path))
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
