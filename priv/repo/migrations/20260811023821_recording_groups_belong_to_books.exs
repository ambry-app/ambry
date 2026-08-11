defmodule Ambry.Repo.Migrations.RecordingGroupsBelongToBooks do
  use Ecto.Migration

  # A group belongs to a book the way its members do — the "fuzzy season
  # mapping" escape hatch is deliberately closed (operator call, 2026-08-10):
  # an episodic season pins to its primary book. The FK is what lets pickers
  # scope to one book's recordings, empty groups display with context, and
  # a (book, name) unique index make local names like "Graphic Audio"
  # collision-free.
  def up do
    alter table(:recording_groups) do
      add :book_id, references(:books, on_delete: :delete_all)
    end

    # A memberless group can't be placed (only the unreleased admin form
    # could have created one, and none exist in any real database) — the
    # delete trigger records any stragglers for sync.
    execute """
    DELETE FROM recording_groups g
    WHERE NOT EXISTS (SELECT 1 FROM media m WHERE m.recording_group_id = g.id)
    """

    execute """
    UPDATE recording_groups g
    SET book_id = (
      SELECT MIN(m.book_id) FROM media m WHERE m.recording_group_id = g.id
    ),
    updated_at = now()
    """

    # The earlier promotion backfill named unnamed groups after their book's
    # title, so two old sets on one book could now collide — suffix all but
    # the first ahead of the unique index.
    execute """
    UPDATE recording_groups g
    SET name = g.name || ' #' || g.id, updated_at = now()
    WHERE EXISTS (
      SELECT 1 FROM recording_groups other
      WHERE other.book_id = g.book_id AND other.name = g.name AND other.id < g.id
    )
    """

    execute "ALTER TABLE recording_groups ALTER COLUMN book_id SET NOT NULL"

    create unique_index(:recording_groups, [:book_id, :name])
  end

  def down do
    drop unique_index(:recording_groups, [:book_id, :name])

    alter table(:recording_groups) do
      remove :book_id
    end
  end
end
