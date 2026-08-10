defmodule Ambry.Repo.Migrations.ClearStaleIssuesOnImportedItems do
  use Ecto.Migration

  @moduledoc """
  A failed import attempt writes its reason onto the item's `issue`, and
  until now a later successful import didn't clear it — leaving "Couldn't
  add this to the library" in red on rows whose media is in the library.
  An imported item's issue is definitionally stale.
  """

  def up do
    execute("UPDATE inbox_items SET issue = NULL WHERE status = 'imported'")
  end

  def down do
    :ok
  end
end
