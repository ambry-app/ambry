defmodule Ambry.Repo.Migrations.DuplicateDismissals do
  @moduledoc """
  An answer to the duplicates report.

  `Ambry.Inbox.Duplicates` asks sameness the way the importer asks it, which
  is deliberate and which means it pairs a companion series with its parent
  ("Dungeon Crawler Carl: Audio Immersion Tunnel") and two spellings of one
  shelf the operator keeps apart on purpose ("The Mistborn Saga", "The
  Mistborn Trilogy"). Those findings are correct. What was missing was a way
  to answer them.

  A dismissal names the exact set of records it settles, not the folded key
  they collided on, so a set that gains a member is a finding again.
  """

  use Ecto.Migration

  def change do
    create table(:duplicate_dismissals) do
      add :kind, :string, null: false
      add :record_ids, {:array, :bigint}, null: false
      add :dismissed_at, :utc_datetime, null: false
    end

    create unique_index(:duplicate_dismissals, [:kind, :record_ids])
  end
end
