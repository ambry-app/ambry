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
  shape.

  That makes this migration depend on application code, which is normally
  worth avoiding, so it depends on as little of it as it can: the two columns
  it needs by name, and a schemaless update. **Selecting the struct is what
  goes wrong.** `Repo.all(InboxItem)` names every field the schema has
  *today*, so the next column added to `inbox_items` broke this migration for
  every fresh install — the column does not exist yet at the point in history
  where this runs. It failed on `lock_version` in CI, on a build whose only
  change was adding it.

  The rows it touches still belong to an installation whose drafts and code
  are the same age; a fresh install has an empty queue and this does nothing
  but ask.
  """

  use Ecto.Migration

  import Ecto.Query

  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  def up do
    InboxItem
    |> where([i], not is_nil(i.draft))
    |> select([i], {i.id, i.draft})
    |> Repo.all()
    |> Enum.each(fn {id, draft} ->
      "inbox_items"
      |> where([i], i.id == ^id)
      |> Repo.update_all(set: [search_text: InboxItem.search_text(draft)])
    end)
  end

  def down do
    Repo.update_all("inbox_items", set: [search_text: nil])
  end
end
