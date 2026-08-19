defmodule Ambry.Repo.Migrations.IndexPenNames do
  @moduledoc """
  Authors, narrators and universes become records of their own.

  No schema change — `search_index` already holds whatever the drain writes
  into it. What this does is mark them dirty, so the first drain after boot
  builds them. The triggers that keep them current were installed with the
  queue and have been enqueueing these references all along; nothing was
  reading them.
  """

  use Ecto.Migration

  def up do
    execute("INSERT INTO search_index_queue (type, id) SELECT 'author', id FROM authors")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'narrator', id FROM narrators")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'universe', id FROM universes")
  end

  def down do
    execute("DELETE FROM search_index WHERE (reference).type IN ('author','narrator','universe')")
  end
end
