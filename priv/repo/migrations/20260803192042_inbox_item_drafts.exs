defmodule Ambry.Repo.Migrations.InboxItemDrafts do
  use Ecto.Migration

  def change do
    alter table(:inbox_items) do
      # The staged import: every decision this release implies, before any of
      # it is real. Held here rather than in staging tables so half-curated
      # discoveries never touch the library tables.
      add :draft, :map

      # Derived from the draft by `Draft.resolved?/1`, denormalized so the
      # queue can filter and count in SQL. Written only by the draft-save
      # path, which is what keeps it from drifting away from the function
      # that defines it.
      add :ready, :boolean, null: false, default: false
    end

    create index(:inbox_items, [:ready], where: "status = 'pending'")
  end
end
