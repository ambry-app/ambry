defmodule Ambry.Repo.Migrations.BooksUniversesJoin do
  use Ecto.Migration
  use Familiar

  def up do
    # the universes table predates any UI; make its name required like series
    execute "UPDATE universes SET name = 'Unnamed universe' WHERE name IS NULL"
    execute "ALTER TABLE universes ALTER COLUMN name SET NOT NULL"

    create table(:books_universes) do
      add :book_id, references(:books, on_delete: :delete_all), null: false
      add :universe_id, references(:universes, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:books_universes, [:book_id, :universe_id])
    create index(:books_universes, [:universe_id])

    execute """
    INSERT INTO books_universes (book_id, universe_id, inserted_at, updated_at)
    SELECT id, universe_id, timezone('utc', now()), timezone('utc', now())
    FROM books WHERE universe_id IS NOT NULL
    """

    execute """
    CREATE TRIGGER track_delete_trigger
    BEFORE DELETE ON universes
    FOR EACH ROW
    EXECUTE FUNCTION track_delete('universe');
    """

    execute """
    CREATE TRIGGER track_delete_trigger
    BEFORE DELETE ON books_universes
    FOR EACH ROW
    EXECUTE FUNCTION track_delete('book_universe');
    """

    create_view("universes_flat", version: 1)
    update_view("books_flat", version: 10)
    update_view("media_flat", version: 7)

    alter table(:books) do
      remove :universe_id
    end
  end

  def down do
    alter table(:books) do
      add :universe_id, references(:universes)
    end

    # Best-effort revert: a book in multiple universes keeps only the earliest
    # membership.
    execute """
    UPDATE books SET universe_id = (
      SELECT bu.universe_id FROM books_universes AS bu
      WHERE bu.book_id = books.id
      ORDER BY bu.id
      LIMIT 1
    )
    """

    update_view("books_flat", version: 9)
    update_view("media_flat", version: 6)
    drop_view("universes_flat")

    execute "DROP TRIGGER track_delete_trigger ON universes"

    drop table(:books_universes)

    execute "ALTER TABLE universes ALTER COLUMN name DROP NOT NULL"
  end
end
