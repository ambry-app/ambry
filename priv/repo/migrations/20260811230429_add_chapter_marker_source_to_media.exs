defmodule Ambry.Repo.Migrations.AddChapterMarkerSourceToMedia do
  use Ecto.Migration

  # Where a recording's chapter markers came from, for the whole list. Left
  # NULL for every existing recording on purpose: their chapters were written
  # before anything recorded this, and inventing a source for them would be
  # exactly the confidently-wrong metadata the chapter split exists to
  # prevent. NULL reads as "nobody recorded it", which is true.
  #
  # Per-row title sources need no migration — chapters are an embed in a
  # jsonb column, so a new field simply reads as nil on old rows.
  def change do
    alter table(:media) do
      add :chapter_marker_source, :string
    end
  end
end
