defmodule Ambry.Repo.Migrations.Watches do
  @moduledoc """
  Audiobooks that don't exist yet, and that the operator doesn't want to forget.

  The library can only describe what it holds, so a book the operator is
  waiting for has nowhere to live until it exists — which is exactly when
  remembering it is hard. A watch is that memory: a provider's record of a
  recording, snapshotted, with the date it is expected.

  ## Why the provider record is copied rather than referenced

  A watch outlives the search that made it. Re-fetching to render a list
  would make an offline provider an empty page, and providers revise
  themselves — an edition is retitled, a narrator is corrected, a listing is
  pulled. The snapshot is what the operator chose, and it still renders in a
  year with nothing reachable.

  ## Why there is no `user_id`

  A watch is about the *recording*, not about a person. Two people waiting
  for the same book is still one watch. When user-facing requests arrive they
  get their own table with their own owner; nothing here changes.
  """

  use Ecto.Migration

  def change do
    create table(:watches) do
      # Identity is provider-qualified because ASIN is not identity: it is
      # absent from most historical audio editions and differs per Audible
      # marketplace when present. The snapshot below carries it as one
      # matching key among several instead.
      add :provider, :string, null: false
      add :provider_id, :string, null: false

      # The snapshot: what the operator picked, as it looked when they picked
      # it. Kept as a map rather than columns because it is evidence, not
      # state -- nothing queries into it, and its shape follows the provider
      # structs rather than this table.
      add :edition, :map, null: false, default: %{}

      # Nullable on purpose: "there will be one, no date announced" is a real
      # state, and the honest rendering of it is a watch without a date rather
      # than no watch at all.
      add :expected_release_date, :date

      add :status, :string, null: false, default: "upcoming"
      add :note, :text

      # Set when the watch is satisfied, so the list can say what it became.
      add :media_id, references(:media, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # One watch per recording. Adding the same book twice is a mistake, not a
    # second intention.
    create unique_index(:watches, [:provider, :provider_id])
    create index(:watches, [:status, :expected_release_date])
  end
end
