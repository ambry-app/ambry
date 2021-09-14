defmodule Ambry.Narrators.Narrator do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.People.Person

  schema "narrators" do
    many_to_many :media, Media, join_through: "media_narrators"
    has_many :books, through: [:media, :book]
    belongs_to :person, Person

    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(narrator, attrs) do
    narrator
    |> cast(attrs, [:name, :description, :image_path])
    |> validate_required([:name])
  end
end
