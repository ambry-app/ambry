defmodule Ambry.Repo.Migrations.CreditPositions do
  use Ecto.Migration

  # Which credit comes first, as data rather than an accident.
  #
  # Until now the order of a book's authors, a recording's narrators and a
  # book's series was whatever order the rows happened to be inserted in —
  # `ORDER BY author_link.id` sits in the flat views to this day. That's
  # invisible and unfixable from the admin UI, and for anything the inbox
  # creates it's simply whatever order a metadata provider returned.
  #
  # It also blocks the library naming template (roadmap 3a), which has to
  # answer "which author owns this folder?" and "which series?" for books
  # that have several of each. A designated primary is the decided answer,
  # and a position column is what makes the designation persist.
  #
  # Backfilled from the existing id order so nothing visibly reorders on
  # deploy: today's implicit order becomes today's explicit order.
  @tables [
    {"authors_books", "book_id"},
    {"media_narrators", "media_id"},
    {"books_series", "book_id"}
  ]

  def up do
    for {table, parent} <- @tables do
      alter table(table) do
        add :position, :integer, null: false, default: 0
      end

      execute """
      UPDATE #{table} AS t
      SET position = ordered.row_number - 1
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY #{parent} ORDER BY id) AS row_number
        FROM #{table}
      ) AS ordered
      WHERE t.id = ordered.id
      """

      create index(table, [parent, :position])
    end
  end

  def down do
    for {table, parent} <- @tables do
      drop index(table, [parent, :position])

      alter table(table) do
        remove :position
      end
    end
  end
end
