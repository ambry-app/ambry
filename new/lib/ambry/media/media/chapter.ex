defmodule Ambry.Media.Media.Chapter do
  @moduledoc """
  A chapter
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  @derive {Jason.Encoder, only: [:time, :title]}

  embedded_schema do
    field :time, :decimal
    field :title, :string
  end

  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:time, :title])
    |> validate_required([:time, :title])
  end
end
