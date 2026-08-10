defmodule Ambry.Repo.Migrations.PromoteRecordingGroups do
  use Ecto.Migration
  use Familiar

  # Recording groups become first-class, series-like entities: the name is
  # required, and parts_total moves off each media onto the group (the total is
  # a fact about the set, not about any one part). A part_number is only
  # meaningful inside a group, enforced by CHECK.
  #
  # recording_groups shipped in v1.9.0, so existing rows must be carried, not
  # wiped: staging holds real groups; prod is believed to hold none (confirm
  # with `SELECT count(*) FROM recording_groups` before releasing).
  def up do
    # Orphaned groups (no members) can't be named from a book and hold nothing;
    # the track_delete trigger records them for client sync.
    execute """
    DELETE FROM recording_groups g
    WHERE NOT EXISTS (SELECT 1 FROM media m WHERE m.recording_group_id = g.id)
    """

    # Backfill names from the members' book title ahead of NOT NULL. Touch
    # updated_at so recordingGroupsChangedSince picks the change up.
    execute """
    UPDATE recording_groups g
    SET name = (
      SELECT MIN(b.title)
      FROM media m JOIN books b ON b.id = m.book_id
      WHERE m.recording_group_id = g.id
    ),
    updated_at = now()
    WHERE g.name IS NULL
    """

    # Unreachable in practice (book.title is NOT NULL), but cheap insurance.
    execute "UPDATE recording_groups SET name = 'Unnamed group ' || id, updated_at = now() WHERE name IS NULL"

    alter table(:recording_groups) do
      add :parts_total, :integer
    end

    execute """
    UPDATE recording_groups g
    SET parts_total = sub.total, updated_at = now()
    FROM (
      SELECT recording_group_id, MAX(parts_total) AS total
      FROM media
      WHERE recording_group_id IS NOT NULL
      GROUP BY recording_group_id
    ) sub
    WHERE sub.recording_group_id = g.id AND sub.total IS NOT NULL
    """

    # Media carrying part fields without a group would silently lose their
    # "of M" once the total lives on the group — give each its own singleton
    # group named after its book. (Loop because INSERT ... SELECT can't
    # correlate RETURNING ids back to the media rows.)
    execute """
    DO $$
    DECLARE
      row RECORD;
      gid bigint;
    BEGIN
      FOR row IN
        SELECT m.id, b.title, m.parts_total
        FROM media m JOIN books b ON b.id = m.book_id
        WHERE m.recording_group_id IS NULL
          AND (m.part_number IS NOT NULL OR m.parts_total IS NOT NULL)
      LOOP
        INSERT INTO recording_groups (name, parts_total, show_label, inserted_at, updated_at)
        VALUES (row.title, row.parts_total, false, now(), now())
        RETURNING id INTO gid;

        UPDATE media SET recording_group_id = gid WHERE id = row.id;
      END LOOP;
    END
    $$
    """

    # The view must stop selecting media.parts_total before the column drop.
    update_view("media_flat", version: 14, revert: 13)

    alter table(:media) do
      remove :parts_total
    end

    execute "ALTER TABLE recording_groups ALTER COLUMN name SET NOT NULL"

    create constraint(:recording_groups, :recording_groups_parts_total_positive,
             check: "parts_total IS NULL OR parts_total >= 1"
           )

    create constraint(:media, :media_part_number_requires_group,
             check: "part_number IS NULL OR recording_group_id IS NOT NULL"
           )
  end

  def down do
    drop constraint(:media, :media_part_number_requires_group)
    drop constraint(:recording_groups, :recording_groups_parts_total_positive)

    execute "ALTER TABLE recording_groups ALTER COLUMN name DROP NOT NULL"

    alter table(:media) do
      add :parts_total, :integer
    end

    execute """
    UPDATE media m
    SET parts_total = g.parts_total
    FROM recording_groups g
    WHERE g.id = m.recording_group_id AND g.parts_total IS NOT NULL
    """

    update_view("media_flat", version: 13, revert: 14)

    alter table(:recording_groups) do
      remove :parts_total
    end
  end
end
