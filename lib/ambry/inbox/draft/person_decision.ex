defmodule Ambry.Inbox.Draft.PersonDecision do
  @moduledoc """
  One human this import will create or reuse, decided once.

  ## Why people are a level, not a decoration on a credit

  Everything the form does well it does by asking three separate questions —
  **outcome** (which thing is this), **evidence** (which records describe it),
  **preference** (which record each field takes its value from). Works get
  that. Recordings get that. People got a name string and a photo picker
  bolted onto a credit, which is why they arrived empty: nothing was ever
  *asked* about a person, so nothing could be answered.

  A person is the same shape as the other two levels and now says so.
  `identity` is the outcome, `sources` is the evidence, and `name`, `image`
  and `description` are ordinary `Field`s with candidates — so the doubt
  banner, `record_row`, `proposal_chip` and the confidence rules all apply
  unchanged.

  ## One per distinct human, which is what a key buys

  A credit used to *embed* the people behind it, so an author who reads their
  own book produced two `PersonRef`s that had to be kept in step by hand —
  `Draft.Edit` mirrored every photo, bio and rename across every other place
  the same human appeared, and every operation had to remember to. One human
  is now one record by construction: credits reference a person by `key`, and
  two credits naming the same human hold the same key.

  That deletes the mirroring rather than fixing it. It also deletes the class
  of bug it existed to prevent — two rows holding different photos of one
  person is no longer a state the model can represent.

  ## `distinct` becomes two keys, not a flag

  "The identically-named person on the other credit is somebody else" used to
  be a boolean, and grouping had to happen where the *positions* were known
  because two rows both marked distinct were otherwise indistinguishable.
  Splitting a decision mints a genuinely new key instead, so the escape hatch
  produces exactly what it claims: two people.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.SourceRef

  @primary_key false

  embedded_schema do
    # How credits refer to this human. Minted from the name at seed time and
    # then **stable**: renaming a person must not re-point the credits that
    # reference them, which is exactly what deriving the key from the current
    # name would do.
    field :key, :string

    # link = a Person already in the library; create = a new one
    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    field :person_id, :id

    field :approved, :boolean, default: false

    # Set the moment the operator touches this person, so re-deriving from a
    # changed record set never discards a photo they went and found.
    field :curated, :boolean, default: false

    # Set when the operator ticks or unticks a record — evidence curation is
    # its own act: adding or renaming a person must not freeze their ticks
    # (that's `curated`), but a hand-picked ticked set must survive a refresh.
    field :evidence_curated, :boolean, default: false

    # Why nothing was adopted, mirroring the work and recording levels. A
    # person nobody could find is a normal outcome, not a failure — plenty of
    # narrators are in no database at all.
    field :doubt, Ecto.Enum, values: [:none, :nothing_found, :low_confidence]
    field :doubt_detail, :string

    # Which provider records describe this human. The records live on the
    # item's `matches["people"][key]` because they're evidence; which of them
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

  Linking answers itself: the Person already in the library has their own name,
  photo and biography, and an import may never overwrite that curation. So only
  the identity is decided here.

  Creating needs a **name** and nothing else. A photo and a biography are
  genuinely optional — plenty of narrators have neither anywhere — and making
  them required would put an unresolvable decision on the form for every human
  no database has heard of, which is the opposite of the invariant's purpose.
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

  Falls back to the key, because a person whose name is blank is precisely the
  case that needs naming and "Person: " with nothing after it names nothing.
  """
  def label(%__MODULE__{} = person), do: Field.value(person.name) || person.key

  @doc """
  Whether the operator has said this provider record describes this human.
  """
  def uses?(%__MODULE__{sources: sources}, record),
    do: Enum.any?(sources, &SourceRef.points_at?(&1, record))

  @doc """
  A key for a human this draft doesn't have a decision for yet.

  Splitting is the `distinct` escape hatch: the second Andy Weir gets a key of
  their own rather than a flag, so the two are told apart by identity instead
  of by where they happen to sit. Suffixes count up so a third is possible.
  """
  def split_key(base, taken) do
    Enum.find_value(2..100, fn n ->
      candidate = "#{base}##{n}"
      if candidate not in taken, do: candidate
    end)
  end
end
