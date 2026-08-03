defmodule Ambry.Repo.Migrations.InboxItems do
  use Ecto.Migration

  # The inbox is the only road into the library (roadmap 3b): everything
  # discovered lands here first and becomes real records only on approval.
  #
  # Inbox items deliberately live in their own table rather than as `pending`
  # Media: half-curated discoveries must never drag placeholder Books,
  # Authors and Series into the library tables before anyone has confirmed
  # them.
  #
  # An item references files exactly where they landed. Nothing is copied,
  # linked, moved or organized at discovery time — file operations happen at
  # approval, per the custody model.
  def change do
    create table(:inbox_items) do
      timestamps(type: :utc_datetime)

      # Absolute path of the candidate: the release folder, or a loose file.
      # This is the item's identity, so a rescan updates rather than
      # duplicates, and a dismissed item is never resurrected.
      add :path, :text, null: false
      add :files, {:array, :text}, null: false, default: []

      add :status, :text, null: false, default: "pending"

      # What the files are (probe) and what they claim about themselves
      # (tags). Both are staging-area facts, not curation, so they live as
      # jsonb rather than earning columns.
      add :probe, :map
      add :tags, :map

      # Why this can't be imported as-is (multi-file, unreadable, …). Shown
      # in the admin UI; never a reason to hide the item.
      add :issue, :text

      # Set on approval — the media this item became.
      add :media_id, references(:media, on_delete: :nilify_all)
    end

    create unique_index(:inbox_items, [:path])
    create index(:inbox_items, [:status])
    create index(:inbox_items, [:media_id])
  end
end
