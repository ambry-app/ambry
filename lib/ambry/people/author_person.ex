defmodule Ambry.People.AuthorPerson do
  @moduledoc """
  Join table between authors and people.

  An author (pen name) can belong to multiple people (e.g. James S.A. Corey is
  Daniel Abraham and Ty Franck), and a person can write under multiple author
  names.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Ecto.EntityRef
  alias Ambry.People.Author
  alias Ambry.People.Person

  schema "authors_people" do
    belongs_to :author, Author
    belongs_to :person, Person

    timestamps(type: :utc_datetime)
  end

  @doc """
  The person behind an author being created by a credit.

  The mirror of `changeset/2`: here the person is what's new, and their name
  comes from the credit unless the form supplied one.
  """
  def credited_changeset(author_person, attrs, credited_name) do
    attrs = named_person(attrs, credited_name)

    author_person
    |> cast(attrs, [:person_id])
    |> EntityRef.cast_new(:person, :person_id)
    |> unique_constraint([:author_id, :person_id])
  end

  # No nested person when the row already says which one it means: a pen
  # name added to somebody the library has must not make a second of them.
  defp named_person(attrs, credited_name) do
    if attrs["person_id"] in [nil, ""] do
      attrs
      |> Map.put_new("person", %{})
      |> update_in(["person"], &Map.put_new(&1, "name", credited_name))
    else
      Map.delete(attrs, "person")
    end
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

  # Neither an id nor nested params means a freshly added form row; the empty
  # nested author is what renders its name input.
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
