defmodule Ambry.Series.SeriesFlat do
  @moduledoc """
  A flattened view of series.
  """

  use Ecto.Schema

  alias Ambry.Ecto.Types.PersonName

  schema "series_flat" do
    field :name, :string
    field :books, :integer
    field :authors, {:array, PersonName}

    timestamps()
  end
end
