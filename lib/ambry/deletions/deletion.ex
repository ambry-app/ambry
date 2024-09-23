defmodule Ambry.Deletions.Deletion do
  @moduledoc """
  A record of a deletion.
  """

  use Ecto.Schema

  schema "deletions" do
    field :type, Ecto.Enum, values: [:person, :book, :series, :media]
    field :record_id, :integer
    field :deleted_at, :utc_datetime
  end
end
