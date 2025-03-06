defmodule Ambry.Utils.DeleteFiles do
  @moduledoc """
  Deletes files from the filesystem.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  import Ambry.Utils, only: [try_delete_files: 1]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"disk_paths" => disk_paths}}) do
    try_delete_files(disk_paths)
  end
end
