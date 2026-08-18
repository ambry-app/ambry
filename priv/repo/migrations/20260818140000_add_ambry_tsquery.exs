defmodule Ambry.Repo.Migrations.AddAmbryTsquery do
  @moduledoc """
  The query side of `ambry_english`, so every caller asks the index the same
  way — with two knobs rather than five hand-rolled implementations.
  """

  use Ecto.Migration
  use Familiar

  def up do
    create_function("ambry_tsquery", version: 1)
  end

  def down do
    drop_function("ambry_tsquery", version: 1)
  end
end
