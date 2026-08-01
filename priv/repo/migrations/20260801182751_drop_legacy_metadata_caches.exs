defmodule Ambry.Repo.Migrations.DropLegacyMetadataCaches do
  use Ecto.Migration

  # Cache-only data (re-fetchable from providers); irreversible is fine.
  def up do
    drop table(:goodreads_cache)
    drop table(:audible_cache)
  end

  def down do
    :ok
  end
end
