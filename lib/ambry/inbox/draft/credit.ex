defmodule Ambry.Inbox.Draft.Credit do
  @moduledoc """
  One credited name, resolved to an `Author` or `Narrator` **identity**.

  A link decision never targets a `Person`: a Person can hold several
  identities, and linking one of them would credit the wrong human on a
  shared pen name. Person appears here only when creating.

  ## The import resolves credits, not personhood

  A credited name *is* an identity. How many humans stand behind it is a fact
  about the person, not about this book, and no provider reports it. So this
  never gates on personhood: it defaults to one new person of the same name
  and makes the interesting case reachable.

  Four cases, one control (`person_keys`):

    * the identity already exists — link it, personhood already settled
    * a brand-new name — new identity, one new person, 1:1
    * a Person exists but this identity doesn't — back the new identity with
      that person (a narrator who has now written something, or a known
      author under a new pen name)
    * a shared pen name — back it with two or more people, new or existing

  The last two are the same widget with a different number of entries, which
  is what stops the case space exploding.

  `person_keys` points into `Draft.people`, where each human is decided once,
  rather than embedding a person per credit; see
  `Ambry.Inbox.Draft.PersonDecision`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Inbox.AutoMatch

  @primary_key false

  embedded_schema do
    # what the source credited, which is the identity's name
    field :name, :string
    field :kind, Ecto.Enum, values: [:author, :narrator]

    # What the evidence called them, frozen at seed time: the way back after
    # a rename or an accidental clear.
    field :proposed_name, :string

    field :mode, Ecto.Enum, values: [:link, :create], default: :create
    # when linking: the Author or Narrator id, never a Person id
    field :identity_id, :id

    field :source, :string
    field :approved, :boolean, default: false

    # Set the moment the operator touches this credit. A credit may carry a
    # linked identity, a renamed pen name and two people behind it, none of
    # which survives being re-derived from proposals.
    field :curated, :boolean, default: false

    # Removal is a decision, so it's a tombstone: a deleted row leaves
    # nothing for `Seed.keep_curated/2` to honour and comes straight back on
    # the next reseed. A removed credit stays out of resolution, approval and
    # person references, and renders as a ghost with a restore.
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

  # Only an *approved* credit with nothing behind it is rejected. An
  # unapproved one is allowed to be half-made, blank name included, since
  # clearing the box is the first half of renaming; `resolved?/1` reports it.
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

  Only the credit itself. The people behind it are
  `PersonDecision.resolved?/1`'s question, asked once per human rather than
  once per credit.
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

  The form collapses to a single control when it is.
  """
  def simple?(%__MODULE__{mode: :link}), do: true
  def simple?(%__MODULE__{mode: :create, person_keys: [_only]}), do: true
  def simple?(%__MODULE__{}), do: false

  @doc """
  Why it isn't resolved. A name that matched more than one existing identity
  is `:ambiguous`, since picking the first would credit the wrong human.
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
  identity, backed by one new person of the same name. Never wrong
  expensively, since the person form can split it later.

  A blank name backs nobody: the key IS the name (`AutoMatch.person_key/1`),
  so the first real name mints the person, in `Edit.rename_credit/4`.
  """
  def new_person_default(name) do
    if blank?(name), do: [], else: [AutoMatch.person_key(name)]
  end
end
