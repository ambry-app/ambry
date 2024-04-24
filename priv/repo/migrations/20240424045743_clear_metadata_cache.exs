defmodule Ambry.Repo.Migrations.ClearMetadataCache do
  use Ecto.Migration

  def change do
    execute("TRUNCATE audible_cache;", "")
    execute("TRUNCATE goodreads_cache;", "")
  end
end
