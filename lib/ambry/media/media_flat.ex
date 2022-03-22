defmodule Ambry.Media.MediaFlat do
  @moduledoc """
  A flattened view of media.
  """

  use Ecto.Schema

  alias Ambry.Ecto.Types.PersonName

  schema "media_flat" do
    field :status, Ecto.Enum, values: [:pending, :processing, :error, :ready]
    field :full_cast, :boolean
    field :abridged, :boolean
    field :duration, :decimal
    field :has_chapters, :boolean
    field :book, :string
    field :series, {:array, :string}
    field :universe, :string
    field :authors, {:array, PersonName}
    field :narrators, {:array, PersonName}

    timestamps()
  end
end
