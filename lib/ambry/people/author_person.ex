defmodule Ambry.People.AuthorPerson do
  @moduledoc """
  Join table between authors and people.

  An author (pen name) can belong to multiple people (e.g. James S.A. Corey is
  Daniel Abraham and Ty Franck), and a person can write under multiple author
  names.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.People.Author
  alias Ambry.People.Person

  schema "authors_people" do
    belongs_to :author, Author
    belongs_to :person, Person

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(author_person, attrs) do
    attrs = maybe_put_new_author(author_person, attrs)

    author_person
    |> cast(attrs, [:author_id])
    |> cast_assoc(:author)
    |> validate_author()
    |> unique_constraint([:author_id, :person_id])
  end

  # A brand-new row with neither an author_id (link to an existing author) nor
  # nested author params is a freshly added form row: give it an empty nested
  # author so the form renders a name input for the new pen name.
  defp maybe_put_new_author(%__MODULE__{id: nil}, attrs) when is_map(attrs) do
    has_author? = Map.has_key?(attrs, "author") or Map.has_key?(attrs, :author)
    author_id = Map.get(attrs, "author_id") || Map.get(attrs, :author_id)

    if has_author? or author_id not in [nil, ""] do
      attrs
    else
      Map.put(attrs, "author", %{})
    end
  end

  defp maybe_put_new_author(_author_person, attrs), do: attrs

  # A row either links an existing author (author_id) or carries a nested
  # author (new pen name / rename of a linked one).
  defp validate_author(changeset) do
    if get_field(changeset, :author_id) || get_change(changeset, :author) do
      changeset
    else
      add_error(changeset, :author_id, "can't be blank")
    end
  end
end
