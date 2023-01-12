defmodule Ambry.Narrators.Narrator do
  @moduledoc """
  A narrator reads books.

  Belongs to a Person, so one person can write as multiple narrators.
  """

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
  def changeset(narrator, attrs) do
    narrator
    |> cast(attrs, [:name, :delete])
    |> validate_required([:name])
    |> maybe_apply_delete()
    |> foreign_key_constraint(:delete,
      name: "media_narrators_narrator_id_fkey",
      message:
        "This narrator is in use by one or more media. You must first remove them as a narrator from any associated media."
    )
  end

  defp maybe_apply_delete(changeset) do
    if Ecto.Changeset.get_change(changeset, :delete, false) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
