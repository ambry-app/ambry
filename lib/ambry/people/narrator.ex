defmodule Ambry.People.Narrator do
  @moduledoc """
  A narrator reads books.

  Belongs to a Person, so one person can write as multiple narrators.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Ecto.EntityRef
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

  @doc """
  A narrator created by the credit that names them, with their person.

  A narrator identity cannot exist without a human (`person_id` is not null),
  and one human is one `Person`, so a name typed into a credit box makes both.
  The person is named by the credit unless the form said otherwise.
  """
  def credited_changeset(narrator, attrs) do
    narrator
    |> changeset(named_person(attrs))
    |> cast(named_person(attrs), [:person_id])
    |> EntityRef.cast_new(:person, :person_id)
  end

  # The human is named by the credit unless the form named them, and is not
  # nested at all when the row says which person it means: an identity added
  # to somebody the library already has must not make a second of them.
  defp named_person(attrs) do
    if blank?(attrs["person_id"]) do
      attrs
      |> Map.put_new("person", %{})
      |> update_in(["person"], &Map.put_new(&1, "name", attrs["name"]))
    else
      Map.delete(attrs, "person")
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

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
