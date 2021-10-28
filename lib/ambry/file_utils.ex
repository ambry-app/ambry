defmodule Ambry.FileUtils do
  @moduledoc """
  Utility functions for managing files on disk.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.{Paths, Repo}
  alias Ambry.People.Person

  require Logger

  @doc """
  Checks the given image web_path to see if it's used by any other books or
  people, and if not, attempts to delete it from disk.
  """
  def maybe_delete_image(nil), do: :noop

  def maybe_delete_image(web_path) do
    book_count = Repo.one(from b in Book, select: count(b.id), where: b.image_path == ^web_path)

    person_count =
      Repo.one(from p in Person, select: count(p.id), where: p.image_path == ^web_path)

    if book_count + person_count == 0 do
      disk_path = Paths.web_to_disk(web_path)

      case File.rm(disk_path) do
        :ok ->
          Logger.info(fn -> "Deleted file: #{disk_path}" end)
          :ok

        {:error, posix} ->
          Logger.warn(fn -> "Couldn't delete file (#{posix}): #{disk_path}" end)
          {:error, posix}
      end
    else
      Logger.warn(fn -> "Not deleting file because it's still in use: #{web_path}" end)
      {:error, :still_in_use}
    end
  end
end
