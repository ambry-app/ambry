defmodule Ambry.Repo.Migrations.InboxItemsMissingSince do
  @moduledoc """
  When an inbox item's files stopped being there.

  The queue had no answer for this. A pending item whose files are deleted
  produces no claim during the walk, so nothing refreshes it and nothing
  notices: it keeps its file list, stays in the queue and still looks
  importable, right up until Add fails inside placement with
  `{:source_missing, path}` — after the operator has done all the curation.

  Nullable and reversible, for the same reason `media.missing_since` is: the
  reasons files vanish are ordinary, and a flag that only goes one way turns
  an unplugged NAS into a queue full of permanent errors.
  """

  use Ecto.Migration

  def change do
    alter table(:inbox_items) do
      add :missing_since, :utc_datetime
    end
  end
end
