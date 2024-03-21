defmodule Ambry.People do
  @moduledoc """
  Functions for dealing with People.
  """

  import Ambry.FileUtils
  import Ambry.Utils
  import Ecto.Query

  alias Ambry.People.Person
  alias Ambry.People.PersonFlat
  alias Ambry.PubSub
  alias Ambry.Repo

  @person_direct_assoc_preloads [:authors, :narrators]

  def standard_preloads, do: @person_direct_assoc_preloads

  @doc """
  Returns a limited list of people and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. You can also optionally filter by giving a map with these
  supported keys:

    * `:search` - String: full-text search on names and aliases.
    * `:is_author` - Boolean.
    * `:is_narrator` - Boolean.

  `order` should be a valid atom key, or a tuple like `{:name, :desc}`.

  ## Examples

      iex> list_people()
      {[%PersonFlat{}, ...], true}

  """
  def list_people(offset \\ 0, limit \\ 10, filters \\ %{}, order \\ :name) do
    over_limit = limit + 1

    people =
      offset
      |> PersonFlat.paginate(over_limit)
      |> PersonFlat.filter(filters)
      |> PersonFlat.order(order)
      |> Repo.all()

    people_to_return = Enum.slice(people, 0, limit)

    {people_to_return, people != people_to_return}
  end

  @doc """
  Returns the number of people (authors & narrators).

  Note that `total` will not always be `authors` + `narrators`, because people
  are sometimes both.

  ## Examples

      iex> count_people()
      %{authors: 3, narrators: 2, total: 4}

  """
  @spec count_people :: %{total: integer(), authors: integer(), narrators: integer()}
  def count_people do
    Repo.one(
      from p in PersonFlat,
        select: %{
          total: count(p.id),
          authors: count(fragment("CASE WHEN ? THEN 1 END", p.is_author)),
          narrators: count(fragment("CASE WHEN ? THEN 1 END", p.is_narrator))
        }
    )
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
  def get_person!(id), do: Person |> preload(^@person_direct_assoc_preloads) |> Repo.get!(id)

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
    |> tap_ok(&PubSub.broadcast_create/1)
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
    |> Repo.preload(@person_direct_assoc_preloads)
    |> Person.changeset(attrs)
    |> Repo.update()
    |> tap_ok(&PubSub.broadcast_update/1)
  end

  @doc """
  Deletes a person.

  ## Examples

      iex> delete_person(person)
      :ok

      iex> delete_person(person)
      {:error, {:has_authored_books, books}}

      iex> delete_person(person)
      {:error, {:has_narrated_books, books}}

      iex> delete_person(person)
      {:error, %Ecto.Changeset{}}

  """
  def delete_person(%Person{} = person) do
    case Repo.delete(change_person(person)) do
      {:ok, person} ->
        maybe_delete_image(person.image_path)
        PubSub.broadcast_delete(person)
        :ok

      {:error, changeset} ->
        cond do
          Keyword.has_key?(changeset.errors, :author) ->
            {:error, {:has_authored_books, get_authored_books_list(person)}}

          Keyword.has_key?(changeset.errors, :narrator) ->
            {:error, {:has_narrated_books, get_narrated_books_list(person)}}
        end
    end
  end

  defp get_authored_books_list(person) do
    %{authors: authors} = Repo.preload(person, authors: [:books])
    Enum.flat_map(authors, fn author -> Enum.map(author.books, & &1.title) end)
  end

  defp get_narrated_books_list(person) do
    %{narrators: narrators} = Repo.preload(person, narrators: [:books])
    Enum.flat_map(narrators, fn narrator -> Enum.map(narrator.books, & &1.title) end)
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
end
