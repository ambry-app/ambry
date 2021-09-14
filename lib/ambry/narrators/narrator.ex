defmodule Ambry.Narrators.Narrator do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media

  schema "narrators" do
    many_to_many :media, Media, join_through: "media_narrators"

    has_many :books, through: [:media, :book]

    field :name, :string
    field :description, :string
    field :image_path, :string

    timestamps()
  end

  @doc false
  def changeset(narrator, attrs) do
    narrator
    |> cast(attrs, [:name, :description, :image_path])
    |> validate_required([:name])
  end
end
