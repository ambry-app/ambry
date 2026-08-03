defmodule Ambry.Utils.DeleteFiles do
  @moduledoc """
  Deletes files from the filesystem.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  import Ambry.Utils,
    only: [try_delete_files: 1, try_delete_folders: 1, try_prune_empty_parents: 2]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"disk_paths" => disk_paths} = args}) do
    try_delete_files(disk_paths)

    if Map.has_key?(args, "folder_paths") do
      folder_paths = args["folder_paths"]
      try_delete_folders(folder_paths)

      # Only when the caller says where to stop. Without a boundary this
      # would happily walk up and remove a library root, whose existence is
      # configuration rather than a consequence of holding a book.
      if stop_paths = args["prune_until"] do
        try_prune_empty_parents(folder_paths, stop_paths)
      end
    end

    :ok
  end
end
