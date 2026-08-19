defmodule Ambry.Repo.Migrations.SearchTheInbox do
  @moduledoc """
  The inbox queue gains a real search.

  Inbox rows are paths on disk, not library records, so they get their own
  index rather than being forced into `search_index` — but the same
  `ambry_english` configuration, so an operator's "truly devious" behaves the
  same here as everywhere else.

  `search_text` is filled by the application on the next draft write. Items
  are still findable by path immediately, which is all the filter this
  replaces could do.
  """

  use Ecto.Migration
  use Familiar

  def up do
    alter table(:inbox_items) do
      add :search_text, :text
      add :search_vector, :tsvector
    end

    create_function("update_inbox_search_vector", version: 1)

    execute """
    CREATE TRIGGER update_inbox_tsvector
    BEFORE INSERT OR UPDATE ON inbox_items
    FOR EACH ROW
    EXECUTE FUNCTION update_inbox_search_vector()
    """

    create index(:inbox_items, [:search_vector], name: :inbox_search_vector_idx, using: "GIN")

    # Every existing row gets its vector from the path it already has; the
    # draft half arrives when something next writes one.
    execute("UPDATE inbox_items SET path = path")
  end

  def down do
    execute("DROP TRIGGER update_inbox_tsvector ON inbox_items")
    drop_function("update_inbox_search_vector", version: 1)

    alter table(:inbox_items) do
      remove :search_vector
      remove :search_text
    end
  end
end
