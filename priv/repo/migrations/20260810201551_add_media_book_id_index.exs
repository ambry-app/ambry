defmodule Ambry.Repo.Migrations.AddMediaBookIdIndex do
  use Ecto.Migration

  def change do
    # media has always been joined through book_id (flat views, editions,
    # imported-file lookups) but never had an index on it; the planner priced
    # those lookups as full scans, which pushed the universes_flat estimate
    # past Postgres's JIT thresholds.
    create index(:media, [:book_id])
  end
end
