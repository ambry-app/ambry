defmodule Ambry.Repo.Migrations.InboxItemExcludedFiles do
  use Ecto.Migration

  # Which of the files an item holds are not part of the recording.
  #
  # A second column rather than a shorter `files`, because those are two
  # different questions and only one of them is discovery's. `files` is the
  # ownership ledger: a file missing from it belongs to nobody, and the next
  # scan makes it an inbox item of its own, every hour. So the file stays
  # owned and this says it isn't in the audiobook.
  def change do
    alter table(:inbox_items) do
      add :excluded_files, {:array, :string}, null: false, default: []
    end
  end
end
