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
    field :delete, :boolean, virtual: true

    timestamps()
  end

  @doc false
  def changeset(narrator, %{"delete" => "true"}) do
    %{Ecto.Changeset.change(narrator, delete: true) | action: :delete}
  end

  def changeset(narrator, attrs) do
    narrator
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
