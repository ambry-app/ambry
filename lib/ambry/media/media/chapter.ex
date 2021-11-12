defmodule Ambry.Media.Media.Chapter do
  @moduledoc """
  A chapter
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :time, :decimal
    field :title, :string
  end

  def changeset(chapter, attrs) do
    cast(chapter, attrs, [:time, :title])
  end
end
