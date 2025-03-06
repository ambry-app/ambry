defmodule Ambry.People do
  @moduledoc """
  Functions for dealing with People.
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Author,
      BookAuthor,
      Narrator,
      Person,
      PersonName,
      PersonName.Type,
      PubSub.PersonCreated,
      PubSub.PersonDeleted,
      PubSub.PersonUpdated
    ]

  import Ambry.Utils
  import Ecto.Query

  alias Ambry.Paths
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.People.PersonFlat
  alias Ambry.People.PubSub.PersonCreated
  alias Ambry.People.PubSub.PersonDeleted
  alias Ambry.People.PubSub.PersonUpdated
  alias Ambry.PubSub
  alias Ambry.Repo
  alias Ambry.Search
  alias Ambry.Thumbnails
  alias Ambry.Thumbnails.GenerateThumbnails

  require Logger

  @person_direct_assoc_preloads [:authors, :narrators]

  def person_standard_preloads, do: @person_direct_assoc_preloads

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
          total: count(),
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
    Repo.transact(fn ->
      changeset = Person.changeset(%Person{}, attrs)

      with {:ok, person} <- Repo.insert(changeset),
           :ok <- Search.insert(person),
           {:ok, _job_or_noop} <- generate_thumbnails_async(person),
           {:ok, _job} <- broadcast_person_created(person) do
        {:ok, person}
      end
    end)
  end

  defp broadcast_person_created(%Person{} = person) do
    person
    |> PersonCreated.new()
    |> PubSub.broadcast_async()
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
    Repo.transact(fn ->
      person = Repo.preload(person, @person_direct_assoc_preloads)
      changeset = Person.changeset(person, attrs)

      with {:ok, updated_person} <- Repo.update(changeset),
           :ok <- Search.update(updated_person),
           {:ok, _job_or_noop} <- delete_unused_files_async(person, updated_person),
           {:ok, _job_or_noop} <- generate_thumbnails_async(updated_person),
           {:ok, _job} <- broadcast_person_updated(updated_person) do
        {:ok, updated_person}
      end
    end)
  end

  defp delete_unused_files_async(%Person{} = old_person, %Person{} = new_person) do
    (all_web_paths(old_person) -- all_web_paths(new_person))
    |> Enum.map(&Paths.web_to_disk/1)
    |> try_delete_files_async()
  end

  defp all_web_paths(%Person{} = person) do
    [person.image_path | if(person.thumbnails, do: all_web_paths(person.thumbnails), else: [])]
    |> Enum.uniq()
    |> Enum.filter(& &1)
  end

  defp all_web_paths(%Thumbnails{} = thumbnails) do
    [
      thumbnails.extra_large,
      thumbnails.large,
      thumbnails.medium,
      thumbnails.small,
      thumbnails.extra_small
    ]
  end

  defp broadcast_person_updated(%Person{} = person) do
    person
    |> PersonUpdated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Deletes a person.

  ## Examples

      iex> delete_person(person)
      :ok

      iex> delete_person(person)
      {:error, :has_authored_books}

      iex> delete_person(person)
      {:error, :has_narrated_media}

      iex> delete_person(person)
      {:error, %Ecto.Changeset{}}

  """
  def delete_person(%Person{} = person) do
    Repo.transact(fn ->
      changeset = Person.changeset(person, %{})

      with {:ok, deleted_person} <- Repo.delete(changeset),
           :ok <- Search.delete(deleted_person),
           {:ok, _job_or_noop} <- delete_all_files_async(deleted_person),
           {:ok, _job} <- broadcast_person_deleted(deleted_person) do
        {:ok, deleted_person}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          deleted_person_changeset_error(changeset)
      end
    end)
  end

  defp delete_all_files_async(%Person{} = person) do
    person
    |> all_web_paths()
    |> Enum.map(&Paths.web_to_disk/1)
    |> try_delete_files_async()
  end

  defp broadcast_person_deleted(%Person{} = person) do
    person
    |> PersonDeleted.new()
    |> PubSub.broadcast_async()
  end

  defp deleted_person_changeset_error(%Ecto.Changeset{} = changeset) do
    cond do
      Keyword.has_key?(changeset.errors, :author) ->
        {:error, :has_authored_books}

      Keyword.has_key?(changeset.errors, :narrator) ->
        {:error, :has_narrated_media}
    end
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
  Schedules an Oban job to generate thumbnails for a person asynchronously.
  Only schedules the job if the person has an image path but no thumbnails.

  ## Examples

      iex> generate_thumbnails_async(person)
      {:ok, %Oban.Job{}}

      iex> generate_thumbnails_async(person_with_thumbnails)
      {:ok, :noop}
  """
  def generate_thumbnails_async(%Person{image_path: image_path, thumbnails: nil} = person)
      when is_binary(image_path) do
    %{"person_id" => person.id, "image_path" => image_path}
    |> GenerateThumbnails.new()
    |> Oban.insert()
  end

  def generate_thumbnails_async(_person), do: {:ok, :noop}

  @doc """
  Generate a `%Thumbnails{}` for the given image_web_path and then store it on
  the given person.

  Fails if the given person's image_web_path does not match the given
  image_web_path, which could happen if the person's image_path was changed
  while the thumbnail generation was in progress.
  """
  def update_person_thumbnails!(person_id, image_web_path) do
    thumbnails = Ambry.Thumbnails.generate_thumbnails!(image_web_path)
    person = get_person!(person_id)

    case update_person(person, %{thumbnails: thumbnails}) do
      {:ok, updated_person} ->
        {:ok, updated_person}

      {:error, changeset} ->
        # Delete the new thumbnails from disk, because the update failed.
        Thumbnails.try_delete_thumbnails(thumbnails)

        {:error, changeset}
    end
  end

  # Narrators

  @doc """
  Gets a single narrator.

  Raises `Ecto.NoResultsError` if the Narrator does not exist.
  """
  def get_narrator!(id), do: Narrator |> preload(:person) |> Repo.get!(id)

  @doc """
  Returns all narrators for use in `Select` components.
  """
  def narrators_for_select do
    query = from n in Narrator, select: {n.name, n.id}, order_by: n.name

    Repo.all(query)
  end

  # Authors

  @doc """
  Gets a single author.

  Raises `Ecto.NoResultsError` if the Author does not exist.
  """
  def get_author!(id), do: Author |> preload(:person) |> Repo.get!(id)

  @doc """
  Returns all authors for use in `Select` components.
  """
  def authors_for_select do
    query = from a in Author, select: {a.name, a.id}, order_by: a.name

    Repo.all(query)
  end
end
