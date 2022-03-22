defmodule Ambry.People do
  @moduledoc """
  Functions for dealing with People.
  """

  import Ambry.FileUtils
  import Ecto.Query

  alias Ambry.People.{Person, PersonFlat}
  alias Ambry.Repo

  @doc """
  Returns a limited list of people and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. Also can optionally filter by the given `filter` string.

  ## Examples

      iex> list_people()
      {[%PersonFlat{}, ...], true}

  """
  def list_people(offset \\ 0, limit \\ 10, filter \\ nil) do
    over_limit = limit + 1
    query = from p in PersonFlat, offset: ^offset, limit: ^over_limit, order_by: :name

    query =
      if filter do
        name_query = "%#{filter}%"

        from p in query,
          where:
            ilike(p.name, ^name_query) or
              fragment(
                "EXISTS (SELECT FROM unnest(?) elem WHERE elem ILIKE ?)",
                p.writing_as,
                ^name_query
              ) or
              fragment(
                "EXISTS (SELECT FROM unnest(?) elem WHERE elem ILIKE ?)",
                p.narrating_as,
                ^name_query
              )
      else
        query
      end

    people = Repo.all(query)
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
  @spec count_people :: integer()
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
        :ok

      {:error, changeset} ->
        cond do
          Keyword.has_key?(changeset.errors, :author) ->
            {:error, {:has_authored_books, get_authored_books_list(person)}}

          Keyword.has_key?(changeset.errors, :narrator) ->
            {:error, {:has_narrated_books, get_narrated_books_list(person)}}

          true ->
            {:error, changeset}
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

  @doc """
  Gets a person and all of their books (either authored or narrated).

  Books are listed in descending order based on publish date.
  """
  def get_person_with_books!(person_id) do
    query =
      from person in Person,
        left_join: narrators in assoc(person, :narrators),
        left_join: narrated_books in assoc(narrators, :books),
        left_join: narrated_book_authors in assoc(narrated_books, :authors),
        left_join: narrated_book_series_books in assoc(narrated_books, :series_books),
        left_join: narrated_book_series_book_series in assoc(narrated_book_series_books, :series),
        left_join: authors in assoc(person, :authors),
        left_join: authored_books in assoc(authors, :books),
        left_join: authored_book_authors in assoc(authored_books, :authors),
        left_join: authored_book_series_books in assoc(authored_books, :series_books),
        left_join: authored_book_series_book_series in assoc(authored_book_series_books, :series),
        preload: [
          narrators:
            {narrators,
             books:
               {narrated_books,
                [
                  authors: narrated_book_authors,
                  series_books:
                    {narrated_book_series_books, series: narrated_book_series_book_series}
                ]}},
          authors:
            {authors,
             books:
               {authored_books,
                [
                  authors: authored_book_authors,
                  series_books:
                    {authored_book_series_books, series: authored_book_series_book_series}
                ]}}
        ],
        order_by: [desc: narrated_books.published, desc: authored_books.published]

    Repo.get!(query, person_id)
  end
end
