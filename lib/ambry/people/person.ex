defmodule Ambry.People.Person do
  @moduledoc """
  A person with a bio.

  Can be (multiple) authors and narrators. (Not used for users).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Authors.Author
  alias Ambry.Narrators.Narrator

  schema "people" do
    has_many :authors, Author
    has_many :narrators, Narrator

    field :name, :string
    field :description, :string
    field :image_path, :string

    timestamps()
  end

  @doc false
  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :description, :image_path])
    |> cast_assoc(:authors)
    |> cast_assoc(:narrators)
    |> validate_required([:name])
  end
end
