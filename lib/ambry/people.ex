defmodule Ambry.People do
  @moduledoc """
  Functions for dealing with People.
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Author,
      AuthorPerson,
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
  alias Ambry.People.AuthorPerson
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

  @person_direct_assoc_preloads [
    :narrators,
    authors: :people,
    author_people: [author: :people]
  ]

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
  The people already in the library carrying exactly this name.

  Case-insensitive and exact — a *name* is the only handle an import has on a
  human, and anything fuzzier answers the wrong question: "who might this be"
  is a judgement for the operator, while "do we already have them" has to be
  certain before it's allowed to skip asking the providers.

  Returns a list rather than one person because two humans really can share a
  name, and that is precisely the case nothing should resolve automatically.

  ## Examples

      iex> people_named("Andy Weir")
      [%Person{}]

  """
  def people_named(name) when is_binary(name) do
    Person
    |> where([p], fragment("lower(?)", p.name) == ^String.downcase(String.trim(name)))
    |> Repo.all()
  end

  def people_named(_other), do: []

  @doc """
  Creates a person.

  ## Examples

      iex> create_person(%{field: value})
      {:ok, %Person{}}

      iex> create_person(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  Accepts `provenance: %{"field" => source}` in `opts` to record where
  provider-fillable field values came from — see `Ambry.Provenance`.
  """
  def create_person(attrs \\ %{}, opts \\ []) do
    Repo.transact(fn ->
      changeset = Person.changeset(%Person{}, attrs, opts)

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

  Accepts `provenance: %{"field" => source}` in `opts` to record where
  provider-fillable field values came from — see `Ambry.Provenance`.
  """
  def update_person(%Person{} = person, attrs, opts \\ []) do
    Repo.transact(fn ->
      person = Repo.preload(person, @person_direct_assoc_preloads)
      changeset = Person.changeset(person, attrs, opts)

      with {:ok, updated_person} <- Repo.update(changeset),
           :ok <- delete_orphaned_authors(person, changeset),
           :ok <- Search.update(updated_person),
           {:ok, _job_or_noop} <- delete_unused_files_async(person, updated_person),
           {:ok, _job_or_noop} <- generate_thumbnails_async(updated_person),
           {:ok, _job} <- broadcast_person_updated(updated_person) do
        {:ok, updated_person}
      end
    end)
  end

  # Unlinking a pen name from a person must not leave an author with no people
  # behind: authors that lost their last link are deleted (blocked with an
  # error if they're still in use by books).
  defp delete_orphaned_authors(%Person{} = person, %Ecto.Changeset{} = changeset) do
    previously_linked_ids = Enum.map(person.author_people, & &1.author_id)

    orphaned_authors =
      Repo.all(
        from author in Author,
          as: :author,
          where: author.id in ^previously_linked_ids,
          where: not exists(from ap in AuthorPerson, where: ap.author_id == parent_as(:author).id)
      )

    Enum.reduce_while(orphaned_authors, :ok, fn author, :ok ->
      author
      |> Author.changeset(%{})
      |> Repo.delete()
      |> case do
        {:ok, _author} ->
          {:cont, :ok}

        {:error, %Ecto.Changeset{} = author_changeset} ->
          {message, _opts} = author_changeset.errors[:id]

          {:halt,
           {:error,
            changeset
            |> Ecto.Changeset.add_error(:author_people, "#{author.name}: #{message}")
            |> Map.put(:action, :update)}}
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

      with :ok <- delete_exclusive_authors(person),
           {:ok, deleted_person} <- Repo.delete(changeset),
           :ok <- Search.delete(deleted_person),
           {:ok, _job_or_noop} <- delete_all_files_async(deleted_person),
           {:ok, _job} <- broadcast_person_deleted(deleted_person) do
        {:ok, deleted_person}
      else
        {:error, :has_authored_books} ->
          {:error, :has_authored_books}

        {:error, %Ecto.Changeset{} = changeset} ->
          deleted_person_changeset_error(changeset)
      end
    end)
  end

  # Deleting a person cascades their author links away, so authors exclusive
  # to this person are deleted up front (composite authors shared with other
  # people survive). Deletion is blocked if an exclusive author still has
  # books.
  defp delete_exclusive_authors(%Person{} = person) do
    exclusive_authors =
      Repo.all(
        from author in Author,
          as: :author,
          join: ap in assoc(author, :author_people),
          on: ap.person_id == ^person.id,
          where:
            not exists(
              from other in AuthorPerson,
                where: other.author_id == parent_as(:author).id and other.person_id != ^person.id
            )
      )

    Enum.reduce_while(exclusive_authors, :ok, fn author, :ok ->
      author
      |> Author.changeset(%{})
      |> Repo.delete()
      |> case do
        {:ok, _author} -> {:cont, :ok}
        {:error, %Ecto.Changeset{}} -> {:halt, {:error, :has_authored_books}}
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
    if Keyword.has_key?(changeset.errors, :narrator) do
      {:error, :has_narrated_media}
    else
      {:error, changeset}
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

  @doc """
  Subscribes to all person CRUD messages.
  """
  def subscribe_to_person_crud_messages do
    :ok = PubSub.subscribe(PersonCreated.wildcard_topic())
    :ok = PubSub.subscribe(PersonUpdated.wildcard_topic())
    :ok = PubSub.subscribe(PersonDeleted.wildcard_topic())
  end

  # Narrators

  @doc """
  Gets a single narrator.

  Raises `Ecto.NoResultsError` if the Narrator does not exist.
  """
  def get_narrator!(id), do: Narrator |> preload(:person) |> Repo.get!(id)

  @doc """
  Returns all narrators for use in `Select` components, as rich options:
  the person's portrait, and their real name when the stage name hides it.
  """
  def narrators_for_select do
    Narrator
    |> preload(:person)
    |> order_by(asc: :name)
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.id,
        label: &1.name,
        image: portrait(List.wrap(&1.person)),
        detail: backing(&1.name, List.wrap(&1.person))
      }
    )
  end

  # Authors

  @doc """
  Gets a single author.

  Raises `Ecto.NoResultsError` if the Author does not exist.
  """
  def get_author!(id), do: Author |> preload(:people) |> Repo.get!(id)

  @doc """
  Returns all authors for use in `Select` components, as rich options: a
  portrait, and the human(s) behind a pen name when that's worth saying.
  """
  def authors_for_select do
    Author
    |> preload(:people)
    |> order_by(asc: :name)
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.id,
        label: &1.name,
        image: portrait(&1.people),
        detail: backing(&1.name, &1.people)
      }
    )
  end

  defp portrait(people) do
    Enum.find_value(people, &(&1.thumbnails && &1.thumbnails.extra_small))
  end

  @doc """
  Who is really behind each identity, when that's worth saying.

  Maps identity id to the backing people's names, only for identities where
  the names add something — a pen name's real names, a stage name's real
  person, a shared pen name's several humans. An identity whose person is
  simply named the same is omitted; repeating the name is noise.
  """
  def author_backing_names do
    Author
    |> preload(:people)
    |> Repo.all()
    |> Map.new(fn author -> {author.id, backing(author.name, author.people)} end)
    |> Map.reject(fn {_id, names} -> names == nil end)
  end

  def narrator_backing_names do
    Narrator
    |> preload(:person)
    |> Repo.all()
    |> Map.new(fn narrator ->
      {narrator.id, backing(narrator.name, List.wrap(narrator.person))}
    end)
    |> Map.reject(fn {_id, names} -> names == nil end)
  end

  defp backing(identity_name, people) do
    case Enum.map(people, & &1.name) do
      [] -> nil
      [^identity_name] -> nil
      names -> Enum.join(names, " and ")
    end
  end

  @doc """
  Returns all people for use in `Select` components.

  People rather than identities: this is what the import form's "who is behind
  this credit" control picks from, where the answer is a human, not a name
  they publish under.
  """
  def people_for_select do
    Person
    |> order_by(asc: :name)
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.id,
        label: &1.name,
        image: &1.thumbnails && &1.thumbnails.extra_small,
        detail: nil
      }
    )
  end
end
