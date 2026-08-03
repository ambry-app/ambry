defmodule Ambry.Repo.Migrations.MediaFlatMissingSince do
  use Ecto.Migration
  use Familiar

  # Surfaces `missing_since` on the admin media list. A nightly sweep whose
  # findings appear nowhere isn't worth running.
  def up, do: update_view("media_flat", version: 13)
  def down, do: update_view("media_flat", version: 12)
end
