defmodule Ambry.Repo.Migrations.RenameInboxItemStatuses do
  use Ecto.Migration

  @moduledoc """
  The item statuses say what happened, in the operator's words: an item that
  was approved *is in the library* — "imported" — and a dismissed one is
  "ignored". "Approved" also collided with the drafts' per-decision approved
  state, which is a genuinely different thing and keeps the name.
  """

  def up do
    execute("UPDATE inbox_items SET status = 'imported' WHERE status = 'approved'")
    execute("UPDATE inbox_items SET status = 'ignored' WHERE status = 'dismissed'")
  end

  def down do
    execute("UPDATE inbox_items SET status = 'approved' WHERE status = 'imported'")
    execute("UPDATE inbox_items SET status = 'dismissed' WHERE status = 'ignored'")
  end
end
