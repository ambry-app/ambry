defmodule Ambry.Repo.Migrations.SupersedeReplacedImports do
  @moduledoc """
  Which import a recording is actually served from.

  A replacement links a second inbox item to a recording another item already
  claims, and nothing said the first one had been superseded. Both rows went
  on rendering as the audiobook, and one of them was describing files that no
  longer exist.

  ## Why it has to be recorded rather than worked out

  Because the trail on disk does not survive the import. A file can arrive by
  hardlink, symlink, copy or move, and a `move` leaves no source to compare
  against; the replacement then deletes the library copy the superseded item
  produced, so both ends can be gone. Matching bytes answers this for some
  imports and not others, which is worse than not answering it.

  What *is* reliable is the write path: a replacement is the only way a
  second item comes to name one recording, so the item that linked last is
  the one the recording is served from. That is a fact about the code, not
  about the files, and it is true whatever placement did.

  ## The backfill

  Chains the existing rows by that rule — each item's successor is the next
  one to link to the same recording. Production has three such pairs, and
  their probes happen to corroborate it (in each, the later item's probed
  size matches the recording's live track exactly). That check is why this is
  safe to run, not how it works: it is unavailable in general for the reasons
  above.

  The partial index is the invariant the whole design rests on — a recording
  has at most one import that has not been superseded — enforced rather than
  remembered, so a future path that forgets to supersede fails loudly instead
  of quietly recreating this bug.
  """

  use Ecto.Migration

  def up do
    alter table(:inbox_items) do
      add :superseded_by_id, references(:inbox_items, on_delete: :nilify_all)
    end

    create index(:inbox_items, [:superseded_by_id])

    # `lead` over the items sharing a recording, oldest first: everyone but
    # the last gets the next one as their successor. `updated_at` is the
    # import moment for an imported item — nothing writes to one afterwards,
    # a scan skips them and every write path refuses them — and `id` breaks
    # a tie that a same-second pair could otherwise leave undefined.
    execute """
    WITH ordered AS (
      SELECT id,
             lead(id) OVER (PARTITION BY media_id ORDER BY updated_at, id) AS successor_id
      FROM inbox_items
      WHERE media_id IS NOT NULL AND status = 'imported'
    )
    UPDATE inbox_items i
    SET superseded_by_id = o.successor_id
    FROM ordered o
    WHERE o.id = i.id AND o.successor_id IS NOT NULL
    """

    create unique_index(:inbox_items, [:media_id],
             where: "media_id IS NOT NULL AND superseded_by_id IS NULL AND status = 'imported'",
             name: :inbox_items_one_live_import_per_media
           )
  end

  def down do
    drop index(:inbox_items, [:media_id], name: :inbox_items_one_live_import_per_media)
    drop index(:inbox_items, [:superseded_by_id])

    alter table(:inbox_items) do
      remove :superseded_by_id
    end
  end
end
