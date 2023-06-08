defmodule Ambry.SupplementalFile do
  @moduledoc """
  An uploaded file
  """

  use Ecto.Schema

  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:filename, :path]}

  embedded_schema do
    field :filename, :string
    field :path, :string
  end

  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:filename, :path])
    |> validate_required([:filename, :path])
  end
end
