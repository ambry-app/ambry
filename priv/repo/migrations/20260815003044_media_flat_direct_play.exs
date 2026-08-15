defmodule Ambry.Repo.Migrations.MediaFlatDirectPlay do
  use Ecto.Migration
  use Familiar

  # A recording with no tracks can only be served by the legacy transcoding
  # pipeline, which the overview reports as something to clear rather than as
  # a fact about the schema. Making it a view column is what lets that number
  # be a link: a count of a thing the operator can't then go and look at is
  # only half an answer.
  def up, do: update_view("media_flat", version: 15)
  def down, do: update_view("media_flat", version: 14)
end
