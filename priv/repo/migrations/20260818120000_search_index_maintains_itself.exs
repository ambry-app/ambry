defmodule Ambry.Repo.Migrations.SearchIndexMaintainsItself do
  @moduledoc """
  The search index stops depending on anyone remembering to update it.

  Three things happen here. A text search configuration that folds accents, so
  "Rodriguez" finds "Patricia Rodríguez" in the index and not only in a
  typeahead. A queue of dirty references, filled by row triggers on every
  table the index reads, so a write by any path — including
  `Ambry.Inbox.Importer`, which is walled off from `Ambry.Search` by its
  boundary and could never have called it — marks what it invalidated. And the
  removal of `search_index.dependencies`, a hand-maintained second copy of the
  reference graph that the foreign keys already describe.
  """

  use Ecto.Migration
  use Familiar

  # (reference type, id column) pairs per table. A join passes two, so that
  # deleting the row reindexes both sides while it can still see them.
  @sources [
    {"books", [{"book", "id"}]},
    # `media` enqueues its book directly rather than leaving the drain to look
    # it up: on a delete the media row is already gone, and `book_id` is the
    # only place the association survives.
    {"media", [{"book", "book_id"}]},
    {"series", [{"series", "id"}]},
    {"universes", [{"universe", "id"}]},
    {"authors", [{"author", "id"}]},
    {"narrators", [{"narrator", "id"}, {"person", "person_id"}]},
    {"people", [{"person", "id"}]},
    {"books_series", [{"book", "book_id"}, {"series", "series_id"}]},
    {"authors_books", [{"book", "book_id"}, {"author", "author_id"}]},
    {"authors_people", [{"author", "author_id"}, {"person", "person_id"}]},
    {"books_universes", [{"book", "book_id"}, {"universe", "universe_id"}]},
    {"media_narrators", [{"media", "media_id"}, {"narrator", "narrator_id"}]}
  ]

  def up do
    # `unaccent` prepended to every token's dictionary chain. The ascii token
    # types are left alone: they cannot carry an accent by definition.
    execute("CREATE TEXT SEARCH CONFIGURATION ambry_english (COPY = pg_catalog.english)")

    execute("""
    ALTER TEXT SEARCH CONFIGURATION ambry_english
      ALTER MAPPING FOR word, hword, hword_part
      WITH unaccent, english_stem
    """)

    # Same arguments and return type, so the dependent trigger survives.
    replace_function("update_index_search_vector", version: 2, revert: 1)

    create table(:search_index_queue, primary_key: false) do
      add :type, :text, null: false, primary_key: true
      add :id, :bigint, null: false, primary_key: true
    end

    create_function("enqueue_search_reference", version: 1)

    for {table, refs} <- @sources do
      args =
        refs
        |> Enum.flat_map(fn {type, column} -> [type, column] end)
        |> Enum.map_join(", ", &"'#{&1}'")

      execute("""
      CREATE TRIGGER enqueue_search_reference
      AFTER INSERT OR UPDATE OR DELETE ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION enqueue_search_reference(#{args})
      """)
    end

    # The FKs already know the reference graph; `Ambry.Search.Drain` reads
    # them. This column was the other copy.
    alter table(:search_index) do
      remove :dependencies
    end

    # Every existing vector was built with `pg_catalog.english` and every
    # existing row may predate a write that never reached the index, so the
    # whole thing is dirty. This is the same work the boot Task was doing on
    # every start, done once and then never again.
    execute("INSERT INTO search_index_queue (type, id) SELECT 'book', id FROM books")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'series', id FROM series")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'person', id FROM people")
  end

  def down do
    alter table(:search_index) do
      add :dependencies, {:array, :reference}, null: false, default: []
    end

    create index(:search_index, [:dependencies])

    for {table, _refs} <- @sources do
      execute("DROP TRIGGER enqueue_search_reference ON #{table}")
    end

    drop_function("enqueue_search_reference", version: 1)

    drop table(:search_index_queue)

    replace_function("update_index_search_vector", version: 1)

    execute("DROP TEXT SEARCH CONFIGURATION ambry_english")
  end
end
