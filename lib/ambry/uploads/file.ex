defmodule Ambry.Uploads.File do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  embedded_schema do
    field :path, :string
    field :filename, :string
    field :size, :integer
    field :mime, :string
    field :metadata, :map, default: %{}
  end

  @doc false
  def changeset(file, attrs) do
    cast(file, attrs, [:path, :filename, :size, :mime, :metadata])
  end
end
