defmodule Ambry.Repo.Migrations.IndexBothAnalyses do
  @moduledoc """
  Search stops using a prose analyzer on a catalogue of proper nouns.

  `ambry_english` stems and drops stop words, which is right for a title and
  wrong for a name: English's stop list holds `don` (from "don't"), `will`,
  `can`, `just` and `now`, so "Don Quixote" was indexed as `'quixot'` and
  somebody named Don could not be found at all.

  Dropping the stemmer is not the answer either — it is what lets "kings"
  find King Rat and "memories" find Children of Memory.

  So every record is indexed under both analyses and every query is asked
  under both, OR'd. That is the multi-field technique a real search engine
  uses: analyze a field several ways, let the best match win. A branch that
  finds nothing costs nothing.
  """

  use Ecto.Migration
  use Familiar

  def up do
    execute("CREATE TEXT SEARCH CONFIGURATION ambry_simple (COPY = pg_catalog.simple)")

    execute("""
    ALTER TEXT SEARCH CONFIGURATION ambry_simple
      ALTER MAPPING FOR word, hword, hword_part
      WITH unaccent, simple
    """)

    replace_function("ambry_tsquery", version: 2, revert: 1)
    replace_function("update_index_search_vector", version: 3, revert: 2)
    replace_function("update_inbox_search_vector", version: 2, revert: 1)

    # Every stored vector was built by the old trigger, so all of them are
    # stale. The inbox rebuilds in place; the library goes through the queue
    # the way the reindex button does.
    execute("UPDATE inbox_items SET path = path")

    execute("INSERT INTO search_index_queue (type, id) SELECT 'book', id FROM books")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'series', id FROM series")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'universe', id FROM universes")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'person', id FROM people")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'author', id FROM authors")
    execute("INSERT INTO search_index_queue (type, id) SELECT 'narrator', id FROM narrators")
  end

  def down do
    replace_function("update_inbox_search_vector", version: 1)
    replace_function("update_index_search_vector", version: 2)
    replace_function("ambry_tsquery", version: 1)

    execute("UPDATE inbox_items SET path = path")

    execute("DROP TEXT SEARCH CONFIGURATION ambry_simple")
  end
end
