defmodule Ambry.Repo.Migrations.MediaFlatUnlistedAt do
  use Ecto.Migration
  use Familiar

  # Surfaces `unlisted_at` on the admin media list; admin lists show all
  # recordings, so unlisted rows need a badge and a filter, not an absence.
  def up, do: update_view("media_flat", version: 17)
  def down, do: update_view("media_flat", version: 16)
end
