defmodule Ambry.Repo.Migrations.CollapseCustody do
  @moduledoc """
  Collapses the custody model (PATHS_REFACTOR_PLAN §5.2).

  Ambry now serves from library roots only, and every import places into one
  via a policy (hardlink | symlink | copy | move). That deletes the two
  columns that expressed the old distinction:

    * `media.custody` — "may Ambry touch these files?" is now uniformly
      "yes for the name in my root, never for anything outside it",
      enforced structurally. There are zero `external` rows anywhere this
      migration will run, so nothing is converted.
    * `sources.on_import` — the durability promise (`leave_in_place`) is
      answered by choosing a policy instead: a leave-in-place source
      becomes a `symlink` one, which references the files where they lie
      exactly as before, via a link the library owns.

  Queued inbox items are derived state and their drafts embed both a
  destination `custody` and the old shape of these decisions, so they are
  deleted and discovery repopulates them (operator-confirmed). **Imported
  items survive**: an imported item is the record of what was imported and
  the only thing standing between an already-imported release and its
  resurfacing as a new candidate on the next scan — the library's copies
  are placed in a root, so the ledger cannot recognize the originals.
  Their frozen drafts still carry the old embedded shape, which Ecto
  ignores on load.
  """

  use Ecto.Migration

  def up do
    # Derived state; discovery rebuilds it on the next scan. Imported items
    # are history, not derived state, and stay.
    execute("DELETE FROM inbox_items WHERE status != 'imported'")

    alter table(:media) do
      remove :custody
    end

    # The faithful translation of the old promise, then a default for
    # anything left unset (bring_in sources always carried a policy).
    execute("UPDATE sources SET import_policy = 'symlink' WHERE on_import = 'leave_in_place'")
    execute("UPDATE sources SET import_policy = 'hardlink' WHERE import_policy IS NULL")

    alter table(:sources) do
      remove :on_import
      modify :import_policy, :string, null: false, default: "hardlink"
    end
  end

  def down do
    alter table(:sources) do
      add :on_import, :string
      modify :import_policy, :string, null: true, default: nil
    end

    execute("UPDATE sources SET on_import = 'bring_in'")

    execute("ALTER TABLE sources ALTER COLUMN on_import SET NOT NULL")

    alter table(:media) do
      add :custody, :string, null: false, default: "managed"
    end
  end
end
