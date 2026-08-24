defmodule Ambry.Inbox.Draft.PersonDecision do
  @moduledoc """
  One human this import will create or reuse, decided once.

  A person is the same shape as the work and recording levels: `identity` is
  the outcome, `sources` is the evidence, and `name`, `image` and
  `description` are ordinary `Field`s with candidates, so the doubt banner,
  `record_row`, `proposal_chip` and the confidence rules all apply unchanged.

  One human is one record by construction: credits reference a person by
  `key`, and two credits naming the same human hold the same key. An author
  who reads their own book therefore has one photo, one bio and one rename,
  with nothing to mirror.

  "The identically-named person on the other credit is somebody else" mints a
  genuinely new key rather than setting a flag, so two rows that were
  otherwise indistinguishable become two people.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.SourceRef

  @primary_key false

  embedded_schema do
    # How credits refer to this human. Minted from the name at seed time and
    # then stable: renaming a person must not re-point their credits.
    field :key, :string

    # link = a Person already in the library; create = a new one
    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    field :person_id, :id

    field :approved, :boolean, default: false

    # Whether this human's name is theirs rather than the credit's, which is
    # rare enough that the card carries a name box only when it is set. A
    # flag rather than "the names differ", because it is set while they still
    # agree: pseudonym first, real name second.
    field :own_name, :boolean, default: false

    # Set the moment the operator touches this person, so re-deriving never
    # discards a photo they went and found.
    field :curated, :boolean, default: false

    # Its own act: renaming a person must not freeze their ticks, but a
    # hand-picked ticked set must survive a refresh.
    field :evidence_curated, :boolean, default: false

    # Why nothing was adopted, mirroring the work and recording levels. A
    # person nobody could find is a normal outcome.
    field :doubt, Ecto.Enum, values: [:none, :nothing_found, :low_confidence]
    field :doubt_detail, :string

    # The records live on the item's `matches["people"][key]`; which of them
    # count is a decision, so it lives here.
    embeds_many :sources, SourceRef, on_replace: :delete

    embeds_one :name, Field, on_replace: :update
    embeds_one :image, Field, on_replace: :update
    embeds_one :description, Field, on_replace: :update
  end

  @doc false
  def changeset(person, attrs) do
    person
    |> cast(attrs, [
      :key,
      :mode,
      :person_id,
      :approved,
      :own_name,
      :curated,
      :evidence_curated,
      :doubt,
      :doubt_detail
    ])
    |> cast_embed(:sources)
    |> cast_embed(:name)
    |> cast_embed(:image)
    |> cast_embed(:description)
    |> validate_required([:key])
    |> validate_link()
  end

  defp validate_link(changeset) do
    if get_field(changeset, :mode) == :link,
      do: validate_required(changeset, [:person_id]),
      else: changeset
  end

  @doc """
  Whether this person still needs a human.

  Linking answers itself: an import may never overwrite an existing Person's
  curation. Creating needs a name and nothing else — a photo and a biography
  are genuinely optional.
  """
  def resolved?(%__MODULE__{approved: false}), do: false
  def resolved?(%__MODULE__{mode: :link, person_id: id}), do: not is_nil(id)
  def resolved?(%__MODULE__{mode: :create} = person), do: named?(person)

  @doc "Whether this person actually says who they are."
  def named?(%__MODULE__{name: name}), do: not is_nil(Field.value(name))

  @doc """
  Why it isn't resolved, for the operator-facing unresolved list.
  """
  def state(%__MODULE__{} = person) do
    cond do
      resolved?(person) -> :approved
      person.mode == :create and not named?(person) -> :missing
      true -> :unconfirmed
    end
  end

  @doc """
  What to call this person in a list of outstanding decisions.
  """
  def label(%__MODULE__{} = person), do: Field.value(person.name) || person.key

  @doc """
  Whether the operator has said no record here describes this human: they
  touched the evidence and left nothing ticked. This settles the level rather
  than blocking it, since a name is all it takes to create a person.
  """
  def uncatalogued?(%__MODULE__{sources: [], evidence_curated: true}), do: true
  def uncatalogued?(%__MODULE__{}), do: false

  @doc """
  Whether the operator has said this provider record describes this human.
  """
  def uses?(%__MODULE__{sources: sources}, record),
    do: Enum.any?(sources, &SourceRef.points_at?(&1, record))

  @doc """
  A key for a human this draft doesn't have a decision for yet.

  Suffixes count up, so a third identically-named person is possible.
  """
  def split_key(base, taken) do
    Enum.find_value(2..100, fn n ->
      candidate = "#{base}##{n}"
      if candidate not in taken, do: candidate
    end)
  end
end
