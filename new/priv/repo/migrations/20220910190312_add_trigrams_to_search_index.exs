defmodule Ambry.Repo.Migrations.AddTrigramsToSearchIndex do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    execute("CREATE INDEX primary_trgm_idx ON search_index USING GIN (\"primary\" gin_trgm_ops)")
    execute("CREATE INDEX secondary_trgm_idx ON search_index USING GIN (secondary gin_trgm_ops)")
    execute("CREATE INDEX tertiary_trgm_idx ON search_index USING GIN (tertiary gin_trgm_ops)")
  end

  def down do
    execute("DROP INDEX primary_trgm_idx ON search_index")
    execute("DROP INDEX secondary_trgm_idx ON search_index")
    execute("DROP INDEX tertiary_trgm_idx ON search_index")

    execute("DROP EXTENSION pg_trgm")
  end
end
