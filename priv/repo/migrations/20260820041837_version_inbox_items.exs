defmodule Ambry.Repo.Migrations.VersionInboxItems do
  @moduledoc """
  Gives an inbox item a version, so a write based on a copy of the row that
  has since moved is refused instead of landing.

  Measured in production: the operator picked the audiobook an item was
  replacing, and a sibling import's post-commit sweep — holding a copy of the
  same row read seconds earlier — wrote its whole draft back over the answer.
  The import job then read a draft that said "a new audiobook", found the
  recording decisions in play again, and refused. Nothing failed anywhere; a
  decision simply stopped existing.

  Existing rows start at 1. Nothing reads the number, so there is nothing to
  backfill — the column only has to *change* on every write.
  """

  use Ecto.Migration

  def change do
    alter table(:inbox_items) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
