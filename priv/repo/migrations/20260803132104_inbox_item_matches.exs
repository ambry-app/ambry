defmodule Ambry.Repo.Migrations.InboxItemMatches do
  use Ecto.Migration

  # Auto-match proposals: which work (Book) and which recording (Media) this
  # item probably is.
  #
  # Both levels keep their whole ranked candidate list, not just the winner,
  # along with each candidate's score and the query that produced it — so
  # reviewing the alternatives costs nothing, and re-searching is reserved
  # for when the right answer isn't in the list at all.
  #
  # jsonb rather than tables because these are staging-area proposals with a
  # provider-shaped payload, thrown away or turned into real records at
  # approval.
  def change do
    alter table(:inbox_items) do
      add :matches, :map
    end
  end
end
