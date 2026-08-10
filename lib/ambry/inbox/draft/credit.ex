defmodule Ambry.Inbox.Draft.Credit do
  @moduledoc """
  One credited name, resolved to an `Author` or `Narrator` **identity**.

  A link decision never targets a `Person` — that was the v1.9.0 pen-name bug
  (matching found a Person and linked its first identity, so a James S.A.
  Corey book credited Ty Franck). Person appears here only when creating.

  ## The import resolves credits, not personhood

  A credited name *is* an identity. How many humans stand behind it is a fact
  about the person, not about this book, and no provider reports it —
  Hardcover just says "James S.A. Corey". So this never gates on personhood:
  it defaults to one new person of the same name and makes the interesting
  case reachable.

  Four cases, one control (`person_keys`):

    * the identity already exists — link it, personhood already settled
    * a brand-new name — new identity, one new person, 1:1
    * a Person exists but this identity doesn't — back the new identity with
      that person (a narrator who has now written something, or a known
      author under a new pen name)
    * a shared pen name — back it with two or more people, new or existing

  The last two are the same widget with a different number of entries, which
  is what stops the case space exploding. Importing The Expanse into an empty
  library is the fourth case with two brand-new people: one Author, two
  People, no special composite pathway anywhere.

  ## The people are referenced, not embedded

  `person_keys` points into `Draft.people`, where each human is decided once.
  Credits used to embed a `PersonRef` each, so an author who read their own
  book produced two records of one person that `Draft.Edit` had to mirror
  every edit across. One human is now one `PersonDecision` by construction —
  see that module for why that deletes the mirroring rather than fixing it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.AutoMatch

  @primary_key false

  embedded_schema do
    # what the source credited, which is the identity's name
    field :name, :string
    field :kind, Ecto.Enum, values: [:author, :narrator]

    # What the evidence called them, frozen at seed time — the way back after
    # a rename or an accidental clear. The scalar fields keep their proposals
    # as candidates; a credit's name had no equivalent, so a cleared box lost
    # the provider's spelling with nothing on screen holding it.
    field :proposed_name, :string

    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    # when linking: the Author or Narrator id, never a Person id
    field :identity_id, :id

    field :source, :string
    field :approved, :boolean, default: false

    # Set the moment the operator touches this credit. Field values are cheap
    # to re-derive when the ticked records change; a credit is not — it may
    # carry a linked identity, a renamed pen name, two people behind it — and
    # rebuilding it from proposals threw all of that away every time another
    # record was ticked.
    field :curated, :boolean, default: false

    # Removal is a decision, so it's a tombstone, not a deletion. A deleted
    # row left nothing curated behind, so `Seed.keep_curated/2` re-appended
    # the same proposal on the very next reseed — and there was no way back
    # for the operator who removed it on purpose. A removed credit stays out
    # of resolution, approval and person references, and renders as a ghost
    # with a restore.
    field :removed, :boolean, default: false

    # candidate identities that matched the name, so the operator can choose
    # rather than retype
    embeds_many :candidates, __MODULE__.Match, on_replace: :delete

    # who is behind this credit, as keys into `Draft.people` — only meaningful
    # when creating the identity
    field :person_keys, {:array, :string}, default: []
  end

  defmodule Match do
    @moduledoc """
    An existing identity that could be what this credit means, with the people
    already behind it so the operator can tell two same-named authors apart.
    """

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :identity_id, :id
      field :name, :string
      # "Daniel Abraham and Ty Franck" — the disambiguator when two identities
      # share a name
      field :people, :string
      field :exact, :boolean, default: false
    end

    @doc false
    def changeset(match, attrs) do
      cast(match, attrs, [:identity_id, :name, :people, :exact])
    end
  end

  @doc false
  def changeset(credit, attrs) do
    credit
    |> cast(attrs, [
      :name,
      :proposed_name,
      :kind,
      :mode,
      :identity_id,
      :source,
      :approved,
      :curated,
      :removed,
      :person_keys
    ])
    |> validate_required([:kind])
    |> cast_embed(:candidates)
    |> validate_resolution()
  end

  # Only what can never be legitimate is rejected: an *approved* credit with
  # nothing behind it. An unapproved one is allowed to be half-made, because
  # that's what the operator is doing while they make it — including a blank
  # name, since clearing the box to retype is the first half of renaming.
  # `resolved?/1` reports it instead, and the import button reads that.
  defp validate_resolution(changeset) do
    approved? = get_field(changeset, :approved)

    cond do
      not approved? ->
        changeset

      get_field(changeset, :mode) == :link ->
        validate_required(changeset, [:identity_id])

      blank?(get_field(changeset, :name)) ->
        add_error(changeset, :name, "is needed before this can be imported")

      get_field(changeset, :person_keys) == [] ->
        add_error(changeset, :person_keys, "needs at least one person behind it")

      true ->
        changeset
    end
  end

  defp blank?(nil), do: true
  defp blank?(name) when is_binary(name), do: String.trim(name) == ""

  @doc """
  Whether this credit still needs a human.

  Only the credit itself is judged here. Whether the people behind it are
  finished is `PersonDecision.resolved?/1`'s question, reported separately by
  `Draft.unresolved/1` — one human is one decision now, so asking about them
  once per credit would report the same outstanding person twice on a
  self-narrated book.
  """
  def resolved?(%__MODULE__{approved: true, mode: :link, identity_id: id}), do: not is_nil(id)

  def resolved?(%__MODULE__{approved: true, mode: :create, name: name}) when not is_binary(name),
    do: false

  def resolved?(%__MODULE__{approved: true, mode: :create, person_keys: []}), do: false

  def resolved?(%__MODULE__{approved: true, mode: :create, name: name}),
    do: String.trim(name) != ""

  def resolved?(%__MODULE__{}), do: false

  @doc """
  Whether this credit is the ordinary case: one new person of the same name.

  The form collapses to a single control when it is, because "who is behind
  this name" is a question about the *person* that almost never has an
  interesting answer — and asking it on every import buried the two cases
  where it does.
  """
  def simple?(%__MODULE__{mode: :link}), do: true
  def simple?(%__MODULE__{mode: :create, person_keys: [_only]}), do: true
  def simple?(%__MODULE__{}), do: false

  @doc """
  Why it isn't resolved.

  A name that matched more than one existing identity is `:ambiguous` — two
  people really can share a name, and picking the first is how a library ends
  up crediting the wrong human.
  """
  def state(%__MODULE__{} = credit) do
    cond do
      resolved?(credit) -> :approved
      length(credit.candidates) > 1 -> :ambiguous
      true -> :unconfirmed
    end
  end

  @doc """
  The default resolution for a name nothing in the library matches: create the
  identity, backed by one new person of the same name.

  Never wrong expensively — a placeholder person is fixed in the person form
  by creating the real people and linking this identity to each — which is
  what earns the right to default here rather than stopping to ask.
  """
  def new_person_default(name), do: [AutoMatch.person_key(name)]
end
