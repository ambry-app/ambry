defmodule Ambry.Repo.Migrations.MediaImageAndDescriptionDataMigration do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE
      media
    SET
      image_path = book.image_path,
      description = book.description
    FROM
      books book
    WHERE
      media.book_id = book.id
    """)
  end

  def down do
    :noop
  end
end
