defmodule Ambry.Repo.Migrations.BackfillInboxSearchText do
  @moduledoc """
  Fills `search_text` for the drafts that already exist.

  Without this the column only fills as drafts are next written, which for a
  queue that is hundreds long and already settled means the feature does not
  arrive until each item is touched — and the whole point is finding an item
  you have *not* touched.

  Calls `InboxItem.search_text/1` rather than reaching into the draft's JSON
  from SQL, for the same reason `put_draft/2` does: the draft is a deep
  embedded structure and SQL digging through it would be a second copy of its
  shape. That makes this migration depend on application code, which is
  normally worth avoiding — it is safe here because the only rows it touches
  belong to an installation whose drafts and code are the same age. A fresh
  install has an empty queue.
  """

  use Ecto.Migration

  import Ecto.Query

  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  def up do
    InboxItem
    |> where([i], not is_nil(i.draft))
    |> Repo.all()
    |> Enum.each(fn item ->
      item
      |> Ecto.Changeset.change(search_text: InboxItem.search_text(item.draft))
      |> Repo.update!()
    end)
  end

  def down do
    Repo.update_all(InboxItem, set: [search_text: nil])
  end
end
