defmodule Ambry.Repo.Migrations.RememberPlacementPerPairing do
  @moduledoc """
  Records what the last import from a source into a root actually did.

  Which of hardlink / symlink / copy / move an import uses is a fact about
  the **pairing**, not about either end: whether a hardlink is even possible
  depends on the two paths sharing a filesystem, and "leave the source
  alone" versus "clear the folder out" depends on what the root is for. A
  default stored on the source alone can only ever be right for one root.

  So the default is learned instead of configured. One row per pairing,
  written after a successful import; the next import from that source
  proposes what the last one did. `last_used_at` also orders the rows, which
  is how a source proposes a *root*: the one it most recently imported into.

  Deleting either end takes its preferences with it — a remembered choice
  about a location that no longer exists is not a fact about anything. That
  is why this is `delete_all` where `inbox_items.source_id` is `restrict`:
  an inbox item's stored paths are meaningless without its source, so losing
  one is data loss; losing a preference just means the next import proposes
  a default instead of a memory.
  """

  use Ecto.Migration

  def change do
    create table(:import_preferences) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :library_root_id, references(:library_roots, on_delete: :delete_all), null: false
      add :policy, :string, null: false
      add :last_used_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:import_preferences, [:source_id, :library_root_id])

    # "Which root did this source last go to" is the root default, read on
    # every seed.
    create index(:import_preferences, [:source_id, :last_used_at])
  end
end
