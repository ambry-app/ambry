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
  alias Ambry.Search.Query
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
  How many people the library holds, and how many of them write and read.

  Named for what it is rather than `count_people`, which now answers the
  list's question — one number, under the list's filters. Note that `total`
  will not always be `authors` + `narrators`, because people are sometimes
  both, which is the other reason this was never a count.

  ## Examples

      iex> people_summary()
      %{authors: 3, narrators: 2, total: 4}

  """
  @spec people_summary :: %{total: integer(), authors: integer(), narrators: integer()}
  def people_summary do
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
  Returns the number of people, under the same filters `list_people/4` lists
  with — so a list can say what page it is of.

  A plain integer, and a different question from `people_summary/0`: that one
  answers "what is in the library" for the overview, in three numbers that
  deliberately don't add up (a person is often both an author and a narrator).
  """
  @spec count_people(map()) :: integer()
  def count_people(filters \\ %{}) do
    filters |> PersonFlat.count_query() |> Repo.one()
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
  The author or narrator identity credited under a name, creating whatever is
  missing.

  Curation credits *people*, and until now only the import form could make
  one: an edit form could link a name to somebody the library already had and
  nothing else, so crediting a narrator who was new to the library meant
  leaving the form, making them by hand, and coming back. That asymmetry is
  the thing this arc exists to remove (**operator**, 2026-08-20: "book edit
  forms should be allowed to create authors, people, series, and universes
  inline").

  Three answers, in the order they are tried:

    * nobody of that name — a new `Person` with that identity, and the
      provider recorded as the source of their name,
    * a person who has never been credited that way — they gain the identity
      rather than becoming a second record of the same human,
    * a person already credited that way — the identity whose name matches,
      or their first, because a pen name is a name they publish under and
      the credit names one of them.

  It creates a person with a name and nothing else. Everything a provider
  knows about them beyond it — a photo, a biography — is fetched on their own
  page today; see `EDIT_PARITY_PLAN.md` for where that is going.
  """
  def find_or_create_author(name, opts \\ []), do: credited(:author, name, opts)

  def find_or_create_narrator(name, opts \\ []), do: credited(:narrator, name, opts)

  defp credited(kind, name, opts) do
    source = Keyword.get(opts, :source)

    case Ambry.Search.find_first(name, Person) do
      nil ->
        attrs = Map.put(identity(kind, name), :name, name)
        {:ok, person} = create_person(attrs, provenance: %{"name" => source})

        person |> credits(kind) |> hd()

      %Person{} = person ->
        case credits(person, kind) do
          [] ->
            {:ok, person} = update_person(person, identity(kind, person.name))
            person |> credits(kind) |> hd()

          credits ->
            Enum.find(credits, &(String.downcase(&1.name) == String.downcase(name))) ||
              List.first(credits)
        end
    end
  end

  # An author identity is a row on the join between a person and an author
  # record; a narrator identity hangs off the person directly. Written out
  # per kind rather than derived, because the two shapes are genuinely
  # different and a clever key made a person with an empty author.
  defp identity(:author, name), do: %{author_people: [%{author: %{name: name}}]}
  defp identity(:narrator, name), do: %{narrators: [%{name: name}]}

  # An author identity hangs off the join, a narrator identity off the person.
  defp credits(%Person{} = person, :author),
    do:
      person
      |> Repo.preload(author_people: :author)
      |> Map.fetch!(:author_people)
      |> Enum.map(& &1.author)

  defp credits(%Person{} = person, :narrator),
    do: person |> Repo.preload(:narrators) |> Map.fetch!(:narrators)

  @doc """
  Narrators matching what somebody typed into a picker, as rich options:
  the person's portrait, and their real name when the stage name hides it.

  Found by the stage name and by the person behind it, same as an author.
  """
  def search_narrators(phrase, limit) do
    Narrator
    |> preload(:person)
    |> Query.matching(phrase, :narrator, limit: limit)
    |> Enum.map(&narrator_option/1)
  end

  @doc """
  One narrator as a picker option, or nil.
  """
  def narrator_option(blank) when blank in [nil, ""], do: nil

  def narrator_option(%Narrator{} = narrator) do
    people = List.wrap(narrator.person)

    %{
      id: narrator.id,
      label: narrator.name,
      image: portrait(people),
      shape: :round,
      detail: backing(narrator.name, people)
    }
  end

  def narrator_option(id) do
    Narrator |> preload(:person) |> Repo.get(id) |> narrator_option()
  end

  # Authors

  @doc """
  Gets a single author.

  Raises `Ecto.NoResultsError` if the Author does not exist.
  """
  def get_author!(id), do: Author |> preload(:people) |> Repo.get!(id)

  @doc """
  Authors matching what somebody typed into a picker, as rich options: a
  portrait, and the human(s) behind a pen name when that's worth saying.

  Found by the pen name and by whoever is behind it, so typing "Ty Franck"
  offers the James S.A. Corey author. The pen name is still the answer — it
  is what goes on the book — but the human is often how you recognise which
  one you meant.
  """
  def search_authors(phrase, limit) do
    Author
    |> preload(:people)
    |> Query.matching(phrase, :author, limit: limit)
    |> Enum.map(&author_option/1)
  end

  @doc """
  One author as a picker option, or nil.
  """
  def author_option(blank) when blank in [nil, ""], do: nil

  def author_option(%Author{} = author) do
    %{
      id: author.id,
      label: author.name,
      image: portrait(author.people),
      shape: :round,
      detail: backing(author.name, author.people)
    }
  end

  def author_option(id) do
    Author |> preload(:people) |> Repo.get(id) |> author_option()
  end

  defp portrait(people) do
    Enum.find_value(people, &(&1.thumbnails && &1.thumbnails.extra_small))
  end

  defp backing(identity_name, people) do
    case Enum.map(people, & &1.name) do
      [] -> nil
      [^identity_name] -> nil
      names -> Enum.join(names, " and ")
    end
  end

  @doc """
  People matching what somebody typed into a picker.

  People rather than identities: this is what the import form's "who is behind
  this credit" control picks from, where the answer is a human, not a name
  they publish under.

  Asks the index rather than the `people` table, which is what makes a person
  findable by a name they publish under as well as their own — a person's
  indexed record *is* their pen names, and their own name is only there when
  it differs.
  """
  def search_people(phrase, limit) do
    Person
    |> Query.matching(phrase, :person, limit: limit)
    |> Enum.map(&person_option/1)
  end

  @doc """
  One person as a picker option, or nil.
  """
  def person_option(blank) when blank in [nil, ""], do: nil

  def person_option(%Person{} = person) do
    %{
      id: person.id,
      label: person.name,
      image: person.thumbnails && person.thumbnails.extra_small,
      shape: :round,
      detail: nil
    }
  end

  def person_option(id), do: Person |> Repo.get(id) |> person_option()
end
