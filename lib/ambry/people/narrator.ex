defmodule Ambry.People.Narrator do
  @moduledoc """
  A narrator reads books.

  Belongs to a Person, so one person can write as multiple narrators.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.MediaNarrator
  alias Ambry.People.Person

  schema "narrators" do
    has_many :media_narrators, MediaNarrator
    has_many :media, through: [:media_narrators, :media]
    has_many :books, through: [:media, :book]
    belongs_to :person, Person

    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(narrator, attrs) do
    narrator
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> foreign_key_constraint(:id,
      name: "media_narrators_narrator_id_fkey",
      message:
        "This narrator is in use by one or more media. You must first remove them as a narrator from any associated media."
    )
  end
end
