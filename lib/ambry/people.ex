defmodule Ambry.People do
  @moduledoc """
  Functions for dealing with People.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.People.Person
  alias Ambry.Repo

  @doc """
  Returns a limited list of people and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. Also can optionally filter by the given `filter` string.

  ## Examples

      iex> list_people()
      {[%Person{}, ...], true}

  """
  def list_people(offset \\ 0, limit \\ 10, filter \\ nil) do
    over_limit = limit + 1
    query = from p in Person, offset: ^offset, limit: ^over_limit, order_by: :name

    query =
      if filter do
        name_query = "%#{filter}%"

        from p in query, where: ilike(p.name, ^name_query)
      else
        query
      end

    people = Repo.all(query)
    people_to_return = Enum.slice(people, 0, limit)

    {people_to_return, people != people_to_return}
  end

  @doc """
  Gets a single person.

  Raises `Ecto.NoResultsError` if the Person does not exist.

  ## Examples

      iex> get_person!(123)
      %Person{}

      iex> get_person!(456)
      ** (Ecto.NoResultsError)

  """
  def get_person!(id), do: Person |> preload([:authors, :narrators]) |> Repo.get!(id)

  @doc """
  Creates a person.

  ## Examples

      iex> create_person(%{field: value})
      {:ok, %Person{}}

      iex> create_person(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_person(attrs \\ %{}) do
    %Person{}
    |> Person.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a person.

  ## Examples

      iex> update_person(person, %{field: new_value})
      {:ok, %Person{}}

      iex> update_person(person, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_person(%Person{} = person, attrs) do
    person
    |> Person.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a person.

  ## Examples

      iex> delete_person(person)
      {:ok, %Person{}}

      iex> delete_person(person)
      {:error, %Ecto.Changeset{}}

  """
  def delete_person(%Person{} = person) do
    Repo.delete(person)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking person changes.

  ## Examples

      iex> change_person(person)
      %Ecto.Changeset{data: %Person{}}

  """
  def change_person(%Person{} = person, attrs \\ %{}) do
    Person.changeset(person, attrs)
  end

  @doc """
  Gets a person and all of their books (either authored or narrated).

  Books are listed in descending order based on publish date.
  """
  def get_person_with_books!(person_id) do
    books_query = from b in Book, order_by: [desc: b.published]

    Person
    |> preload(
      authors: [books: ^{books_query, [:authors, series_books: :series]}],
      narrators: [books: ^{books_query, [:authors, series_books: :series]}]
    )
    |> Repo.get!(person_id)
  end
end
