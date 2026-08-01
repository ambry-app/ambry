defmodule Ambry.Repo.Migrations.CompositeAuthors do
  use Ecto.Migration
  use Familiar

  def up do
    create table(:authors_people) do
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :person_id, references(:people, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:authors_people, [:author_id, :person_id])
    create index(:authors_people, [:person_id])

    execute """
    INSERT INTO authors_people (author_id, person_id, inserted_at, updated_at)
    SELECT id, person_id, inserted_at, updated_at FROM authors
    """

    execute """
    CREATE TRIGGER track_delete_trigger
    BEFORE DELETE ON authors_people
    FOR EACH ROW
    EXECUTE FUNCTION track_delete('author_person');
    """

    update_view("people_flat", version: 5)
    update_view("books_flat", version: 9)
    update_view("media_flat", version: 6)
    update_view("series_flat", version: 4)

    alter table(:authors) do
      remove :person_id
    end
  end

  def down do
    alter table(:authors) do
      add :person_id, references(:people, on_delete: :delete_all)
    end

    # Best-effort revert: an author linked to multiple people keeps only the
    # earliest link.
    execute """
    UPDATE authors SET person_id = (
      SELECT ap.person_id FROM authors_people AS ap
      WHERE ap.author_id = authors.id
      ORDER BY ap.id
      LIMIT 1
    )
    """

    execute "ALTER TABLE authors ALTER COLUMN person_id SET NOT NULL"

    update_view("people_flat", version: 4)
    update_view("books_flat", version: 8)
    update_view("media_flat", version: 5)
    update_view("series_flat", version: 3)

    drop table(:authors_people)
  end
end
