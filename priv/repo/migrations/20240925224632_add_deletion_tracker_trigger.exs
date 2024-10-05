defmodule Ambry.Repo.Migrations.AddDeletionTrackerTrigger do
  use Ecto.Migration
  use Familiar

  @tables_to_track %{
    authors: "author",
    authors_books: "book_author",
    books: "book",
    books_series: "series_book",
    media: "media",
    media_narrators: "media_narrator",
    narrators: "narrator",
    people: "person",
    series: "series"
  }

  def up do
    create_function("track_delete", version: 1)

    for {table, type} <- @tables_to_track do
      execute """
      CREATE TRIGGER track_delete_trigger
      BEFORE DELETE ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION track_delete('#{type}');
      """
    end
  end

  def down do
    for {table, _} <- @tables_to_track do
      execute """
      DROP TRIGGER track_delete_trigger ON #{table};
      """
    end

    drop_function("track_delete", version: 1)
  end
end
