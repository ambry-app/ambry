defmodule Ambry.Inbox.Draft.PersonRef do
  @moduledoc """
  One human behind a credit: either somebody already in the library, or
  somebody to create with it.

  Two or more of these on one credit is a shared pen name — that is the whole
  of the composite-author case as far as an import is concerned. There is no
  separate composite mode, because "how many people" is a number, not a kind.

  ## One human, two credits

  A person can be behind more than one credit on the same import, and the
  ordinary case of that is an author who reads their own book. Both credits
  propose creating somebody of the same name, and resolving each in isolation
  made the same human twice — two Person rows, one photo and bio between them,
  and nothing afterwards to say they were ever meant to be one.

  So sameness is decided by `key/1` rather than by which credit a reference
  hangs off: two new people of one name **are** one person unless the operator
  says otherwise, which is what `distinct` says. Two humans who share a name
  and both worked on one audiobook is not a case worth charging every
  self-narrated import a decision for — and where it does happen, saying so is
  one click, on a row that already tells you what it's about to do.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    # set = an existing Person; nil = create one with this name
    field :person_id, :id
    field :name, :string

    # What a *new* person will be created with. 3b's promise is that the
    # operator never has to leave the inbox to finish a leaf entity, and a
    # person with no face is unfinished — every credit imported without these
    # was a trip to the person form afterwards.
    field :description, :string
    field :image_url, :string
    # which provider the photo, bio and name came from, for 1d provenance
    field :image_source, :string
    field :description_source, :string
    field :name_source, :string

    # "the identically-named person on the other credit is somebody else".
    # The escape hatch from the same-person default, and the only thing here
    # that is a claim about the world rather than about this row.
    field :distinct, :boolean, default: false
  end

  # Deliberately permissive: a draft has to be *storable* while it's still
  # being made up, or the operator couldn't add a second person and then name
  # them. Whether it's finished is `complete?/1`'s job, reported through
  # `Draft.unresolved/1` — validation gates saving, the invariant gates
  # importing, and conflating the two makes the form unusable.
  @doc false
  def changeset(person_ref, attrs) do
    cast(person_ref, attrs, [
      :person_id,
      :name,
      :description,
      :image_url,
      :image_source,
      :description_source,
      :name_source,
      :distinct
    ])
  end

  @doc """
  Which human this reference means, as far as one import can tell.

  References sharing a key are one person and are created once. Somebody
  already in the library is keyed by their id; somebody new, by their name,
  because a name is all an import has to go on and two credits proposing to
  create "Andy Weir" mean the one Andy Weir.

  A reference the operator has marked `distinct` never joins a group, but that
  is decided by `Draft.people_groups/1` rather than here: two identical rows
  both marked distinct are told apart only by *where they are*, and a key
  computed from the struct alone silently merged them back together.
  """
  def key(%__MODULE__{person_id: id}) when not is_nil(id), do: {:person, id}
  def key(%__MODULE__{name: name}) when is_binary(name), do: {:new, normalize(name)}
  def key(%__MODULE__{}), do: :unnamed

  defp normalize(name),
    do: name |> String.downcase() |> String.replace(~r/\s+/, " ") |> String.trim()

  @doc """
  Folds a reference into the one it shares a key with.

  Whichever row the operator found the photo or the bio on, the person gets
  it: they went looking on the author row or the narrator row, not on a
  particular row, and the one Person created from both should carry whatever
  either of them found.
  """
  def merge(%__MODULE__{} = held, %__MODULE__{} = other) do
    %{
      held
      | name_source: held.name_source || other.name_source,
        description: held.description || other.description,
        description_source: held.description_source || other.description_source,
        image_url: held.image_url || other.image_url,
        image_source: held.image_source || other.image_source
    }
  end

  @doc "Whether this reference actually says who it means."
  def complete?(%__MODULE__{person_id: id}) when not is_nil(id), do: true
  def complete?(%__MODULE__{name: name}) when is_binary(name), do: String.trim(name) != ""
  def complete?(%__MODULE__{}), do: false

  @doc "Whether this reference means 'create somebody new'."
  def new?(%__MODULE__{person_id: nil}), do: true
  def new?(%__MODULE__{}), do: false
end
